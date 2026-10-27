#!/usr/bin/env python3
"""Use dmgbuild's filesystem layout plus a native, verified Finder bookmark."""
from pathlib import Path
import subprocess,sys,tempfile
import dmgbuild
from ds_store import DSStore, DSStoreEntry
root=Path(__file__).resolve().parent.parent
mounted=None

def remember_mount(mount, options):
    global mounted
    mounted=Path(mount)

def callback(event):
    if event.get('type')=='operation::finished' and event.get('operation')=='dsstore::create':
        with tempfile.TemporaryDirectory(prefix='glance-dmg-bookmark-') as temp:
            bookmark=Path(temp)/'background.bookmark'
            subprocess.run(['swift',str(root/'scripts/dmg-background-bookmark.swift'),str(mounted/'.background.tiff'),str(bookmark)],check=True)
            with DSStore.open(str(mounted/'.DS_Store'),'r+') as store:
                store.insert(DSStoreEntry('.', b'pBBk', b'blob', bookmark.read_bytes()))

dmgbuild.build_dmg(sys.argv[1], 'Install Glance', settings_file=str(root/'packaging/dmg/settings.py'), defines={'root':str(root)}, settings={'create_hook':remember_mount},callback=callback)
