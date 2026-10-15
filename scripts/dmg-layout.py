import pathlib
import sys
from ds_store import DSStore
from mac_alias import Alias

volume = pathlib.Path(sys.argv[1]).resolve()
alias = Alias.for_file(str(volume / '.background' / 'background.png'))
background = alias.to_bytes()
with DSStore.open(str(volume / '.DS_Store'), 'w+') as store:
    store['.']['bwsp'] = {
        'ShowStatusBar': False, 'ShowToolbar': False, 'ShowPathbar': False,
        'ShowSidebar': False, 'ShowTabView': False,
        'ContainerShowSidebar': False, 'WindowBounds': '{{120, 120}, {760, 500}}',
        'PreviewPaneVisibility': False, 'SidebarWidth': 180,
    }
    store['.']['icvp'] = {
        'viewOptionsVersion': 1, 'backgroundType': 2, 'backgroundImageAlias': background,
        'backgroundColorRed': 0.10, 'backgroundColorGreen': 0.10, 'backgroundColorBlue': 0.10,
        'iconSize': 128.0, 'textSize': 16.0, 'labelOnBottom': True,
        'showItemInfo': False, 'showIconPreview': True, 'arrangeBy': 'none',
        'gridSpacing': 100.0, 'gridOffsetX': 0.0, 'gridOffsetY': 0.0,
        'scrollPositionX': 0.0, 'scrollPositionY': 0.0,
    }
    store['.']['vSrn'] = ('long', 1)
    store['.']['vstl'] = ('type', b'icnv')
    store['.']['icvl'] = ('type', b'icnv')
    store['FlowgoSwift.app']['Iloc'] = (205, 225)
    store['Applications']['Iloc'] = (555, 225)
