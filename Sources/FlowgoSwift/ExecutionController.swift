import Foundation
import Combine
import FlowCore

struct WatchedVariable: Identifiable {
    let id: String
    let type: String
    let value: String
    var elements: [String]? = nil
    var elementCount = 0
    init(id: String, type: String, value: String) {
        self.id = id; self.type = type; self.value = value
    }
    init(_ variable: Variable, limit: Int = 200) {
        id = variable.name; type = variable.type
        if case .array(let array) = variable.value {
            elements = array.values.prefix(limit).map(\.description)
            elementCount = array.values.count
            value = "[...]"
        } else { value = variable.value.description }
    }
}

struct WatchedFrame: Identifiable {
    let id: Int
    let name: String
    let variables: [WatchedVariable]
    let parameterNames: Set<String>
}

struct ConsoleLine: Identifiable {
    let id: Int
    let text: String
    let input: Bool
    let breakpoint: Bool
}

final class ExecutionController: ObservableObject {
    @Published var console = ""
    @Published var status = "Ready"
    @Published var running = false
    @Published var paused = false
    @Published var waitingForInput = false
    @Published var inputPrompt = ""
    @Published var currentID: UUID?
    @Published var function = "Main"
    @Published var turtle = TurtleState()
    @Published var callStack: [WatchedFrame] = []
    @Published var variables: [WatchedVariable] = []
    private let condition = NSCondition()
    private var stopped = false
    private var pauseRequested = false
    private var permits = 0
    private var response: String?
    private var pendingOutput = ""
    private var pendingInputRanges: [Range<Int>] = []
    private var inputRanges: [Range<Int>] = []
    private var pendingStatus: String?
    private var pendingPrompt: String?
    private var snapshot: (UUID, String, [WatchedVariable], [WatchedFrame])?
    private var workerPaused = false
    private var finished = false
    private var timer: Timer?
    @Published private(set) var consoleBreakpoints: [Int] = []
    private var pendingBreakpoints: [Int] = []
    private var ignoreBreakpoints = false
    private var outputLineCount = 0
    private var outputUTF16Count = 0
    private var breakpoints = Set<UUID>()
    private var pendingTurtle: TurtleState?
    private var lastDrawing = Date.distantPast
    private var executionDelay: TimeInterval = 0
    private var lastPublished = Date.distantPast

    func start(_ program: Program, stepping: Bool, breakpoints: Set<UUID>, baseDirectory: URL?) {
        guard !running else { return }
        turtle = TurtleState(); console = ""; consoleBreakpoints = []; status = "Running"; running = true; paused = false
        waitingForInput = false; inputPrompt = ""; currentID = nil; function = "Main"; variables = []; callStack = []
        condition.lock()
        stopped = false; pauseRequested = stepping; permits = 0; response = nil
        pendingOutput = ""; pendingInputRanges = []; inputRanges = []; pendingBreakpoints = []; outputLineCount = 0; outputUTF16Count = 0; pendingStatus = nil; pendingPrompt = nil; snapshot = nil
        pendingTurtle = nil; lastDrawing = .distantPast; lastPublished = .distantPast
        workerPaused = false; finished = false; self.breakpoints = breakpoints
        condition.unlock()
        var snapshotIDs = Set(program.functions.map(\.id))
        func collectInputs(_ node: Element) {
            if node.tag == "input" { snapshotIDs.insert(node.id) }
            node.children.forEach(collectInputs)
        }
        collectInputs(program.root)
        let alwaysSnapshot = snapshotIDs
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.flush() }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let interpreter = Interpreter(program)
            if let baseDirectory { interpreter.baseDirectory = baseDirectory }
            interpreter.breakpointsEnabled = { [self] in
                condition.lock(); defer { condition.unlock() }
                return !ignoreBreakpoints
            }
            interpreter.drawing = { [self] state in
                condition.lock()
                if Date().timeIntervalSince(lastDrawing) > 0.05 || pauseRequested {
                    pendingTurtle = state; lastDrawing = Date()
                }
                condition.unlock()
            }
            interpreter.trace = { [self, weak interpreter] trace in
                guard let interpreter else { return }
                condition.lock()
                defer { condition.unlock() }
                if !ignoreBreakpoints && (trace.breakpoint || breakpoints.contains(trace.nodeID)) {
                    pauseRequested = true
                    pendingBreakpoints.append(outputLineCount)
                }
                if pauseRequested || alwaysSnapshot.contains(trace.nodeID) || Date().timeIntervalSince(lastPublished) > 0.05 {
                    let arrayLimit = pauseRequested || alwaysSnapshot.contains(trace.nodeID) ? Int.max : 200
                    snapshot = (trace.nodeID, trace.function, trace.variables.map {
                        WatchedVariable($0,limit:arrayLimit)
                    }, interpreter.callStack.enumerated().map { index,frame in
                        WatchedFrame(id:index,name:frame.name,variables:frame.variables.map { WatchedVariable($0,limit:arrayLimit) },parameterNames:frame.parameterNames)
                    })
                    pendingTurtle = interpreter.turtle
                    lastPublished = Date()
                }
                while pauseRequested && permits == 0 && !stopped {
                    workerPaused = true; condition.wait()
                }
                workerPaused = false
                guard !stopped else { throw FlowError("Stopped") }
                if permits > 0 { permits -= 1 }
                else if !pauseRequested && executionDelay > 0 {
                    condition.wait(until: Date().addingTimeInterval(executionDelay))
                    guard !stopped else { throw FlowError("Stopped") }
                }
            }
            interpreter.output = { [self] text in
                condition.lock()
                if pendingOutput.utf8.count < 1_000_000 { pendingOutput += text; outputLineCount += text.filter { $0 == "\n" }.count; outputUTF16Count += text.utf16.count }
                condition.unlock()
            }
            interpreter.input = { [self] name, type in
                condition.lock()
                defer { condition.unlock() }
                var invalid = false
                while !stopped {
                    pendingPrompt = invalid ? "Invalid value. Enter a value of type \(type) for \(name)" : "Please enter a value of type \(type) for \(name)"
                    response = nil
                    while response == nil && !stopped { condition.wait() }
                    guard !stopped else { throw FlowError("Stopped") }
                    let text = response ?? ""
                    do {
                        _ = try Interpreter.parseInput(text,type:type)
                        pendingPrompt = nil
                        let entry = "> \(text)\n"
                        pendingInputRanges.append(outputUTF16Count..<(outputUTF16Count + entry.utf16.count))
                        outputUTF16Count += entry.utf16.count
                        pendingOutput += entry
                        outputLineCount += text.filter { $0 == "\n" }.count + 1
                        return text
                    } catch { invalid = true }
                }
                throw FlowError("Stopped")
            }
            do {
                try interpreter.run()
                condition.lock(); pendingStatus = "Finished"; condition.unlock()
            } catch {
                condition.lock(); pendingStatus = stopped ? "Stopped" : error.localizedDescription; condition.unlock()
            }
            condition.lock(); pendingTurtle = interpreter.turtle; finished = true; condition.unlock()
        }
    }
    func clearConsole() {
        condition.lock()
        pendingOutput = ""; pendingInputRanges = []; inputRanges = []; pendingBreakpoints = []; outputLineCount = 0; outputUTF16Count = 0
        condition.unlock()
        console = ""; consoleBreakpoints = []
    }
    var consoleText: String {
        let text = NSMutableString(string:console)
        for range in inputRanges.reversed() where range.lowerBound + 2 <= text.length {
            if text.substring(with:NSRange(location:range.lowerBound,length:2)) == "> " {
                text.deleteCharacters(in:NSRange(location:range.lowerBound,length:2))
            }
        }
        return text as String
    }
    func consoleLines(showBreakpoints: Bool) -> [ConsoleLine] {
        var result: [ConsoleLine] = []
        let breakpointCounts = Dictionary(grouping:consoleBreakpoints,by:{ $0 }).mapValues(\.count)
        var offset = 0
        for (index,line) in console.split(separator:"\n",omittingEmptySubsequences:false).enumerated() {
            if showBreakpoints {
                for _ in 0..<(breakpointCounts[index] ?? 0) {
                    result.append(ConsoleLine(id:result.count,text:"Breakpoint: The program was paused.",input:false,breakpoint:true))
                }
            }
            let text = String(line) as NSString
            let end = offset + text.length
            var cursor = offset
            for range in inputRanges where range.lowerBound < end && range.upperBound > offset {
                let start = max(offset,range.lowerBound)
                if cursor < start {
                    result.append(ConsoleLine(id:result.count,text:text.substring(with:NSRange(location:cursor - offset,length:start - cursor)),input:false,breakpoint:false))
                }
                let stop = min(end,range.upperBound)
                var value = text.substring(with:NSRange(location:start - offset,length:stop - start))
                if start == range.lowerBound && value.hasPrefix("> ") { value = String(value.dropFirst(2)) }
                result.append(ConsoleLine(id:result.count,text:value,input:true,breakpoint:false))
                cursor = stop
            }
            if cursor < end || (text.length == 0 && offset < console.utf16.count) {
                result.append(ConsoleLine(id:result.count,text:text.substring(from:cursor - offset),input:false,breakpoint:false))
            }
            offset = end + 1
        }
        return result
    }
    func setIgnoreBreakpoints(_ ignored: Bool) {
        condition.lock(); ignoreBreakpoints = ignored; condition.unlock()
    }
    func setSpeed(_ delay: TimeInterval) {
        condition.lock(); executionDelay = delay; condition.broadcast(); condition.unlock()
    }
    func resume() {
        condition.lock(); pauseRequested = false; permits = 0; condition.broadcast(); condition.unlock()
    }
    func pause() {
        condition.lock(); pauseRequested = true; condition.unlock()
    }
    func step() {
        condition.lock(); pauseRequested = true; permits += 1; condition.broadcast(); condition.unlock()
    }
    func stop() {
        condition.lock(); stopped = true; condition.broadcast(); condition.unlock()
    }
    func submit(_ value: String) {
        condition.lock(); response = value; condition.broadcast(); condition.unlock()
    }
    private func flush() {
        condition.lock()
        let text = pendingOutput; pendingOutput = ""
        let inputs = pendingInputRanges; pendingInputRanges = []
        let breaks = pendingBreakpoints; pendingBreakpoints = []
        let snap = snapshot; snapshot = nil
        let prompt = pendingPrompt
        let isPaused = workerPaused
        let done = finished
        let result = pendingStatus
        let drawing = pendingTurtle; pendingTurtle = nil
        condition.unlock()
        inputRanges += inputs
        if let drawing { turtle = drawing }
        consoleBreakpoints += breaks
        if consoleBreakpoints.count > 2000 { consoleBreakpoints = Array(consoleBreakpoints.suffix(2000)) }
        if !text.isEmpty {
            console += text
            if console.count > 200_000 {
                let retained = String(console.suffix(150_000))
                let removedLines = console.filter { $0 == "\n" }.count - retained.filter { $0 == "\n" }.count
                let removedUnits = console.utf16.count - retained.utf16.count
                console = retained
                inputRanges = inputRanges.compactMap { range in
                    guard range.upperBound > removedUnits else { return nil }
                    return max(0,range.lowerBound - removedUnits)..<(range.upperBound - removedUnits)
                }
                consoleBreakpoints = consoleBreakpoints.compactMap { $0 >= removedLines ? $0 - removedLines : nil }
                condition.lock()
                outputLineCount -= removedLines
                outputUTF16Count -= removedUnits
                pendingInputRanges = pendingInputRanges.compactMap { range in
                    guard range.upperBound > removedUnits else { return nil }
                    return max(0,range.lowerBound - removedUnits)..<(range.upperBound - removedUnits)
                }
                pendingBreakpoints = pendingBreakpoints.compactMap { $0 >= removedLines ? $0 - removedLines : nil }
                condition.unlock()
            }
        }
        if let snap { currentID = snap.0; function = snap.1; variables = snap.2; callStack = snap.3 }
        paused = isPaused
        waitingForInput = prompt != nil
        inputPrompt = prompt ?? ""
        status = prompt != nil ? "Waiting for input" : (isPaused ? "Paused" : "Running")
        if done {
            running = false; paused = false; waitingForInput = false; inputPrompt = ""
            status = result ?? "Finished"
            timer?.invalidate(); timer = nil
        }
    }
    deinit { stop(); timer?.invalidate() }
}
