"""Build reproducible download bundles and copy public docs for the static site."""
from pathlib import Path
import shutil
import zipfile
ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'site/downloads'

def bundle(name,files):
    with zipfile.ZipFile(DEST/name,'w',compression=zipfile.ZIP_DEFLATED) as archive:
        for source,target in sorted(files,key=lambda pair:pair[1]):
            entry=zipfile.ZipInfo(target,date_time=(2026,1,1,0,0,0));entry.compress_type=zipfile.ZIP_DEFLATED
            entry.external_attr=0o644<<16
            archive.writestr(entry,source.read_bytes())

def main():
    DEST.mkdir(parents=True,exist_ok=True)
    common=[(ROOT/'LICENSE','LICENSE'),(ROOT/'README.md','README.md')]+[(p,'spec/'+p.name) for p in (ROOT/'spec').glob('*.md')]
    bundle('cdl-audio-python.zip',common+[(ROOT/'requirements.txt','requirements.txt')]+[(p,p.name) for p in (ROOT/'python').iterdir() if p.is_file()])
    bundle('cdl-audio-javascript.zip',common+[(p,p.name) for p in (ROOT/'site/js').glob('*.mjs')])
    powershell=ROOT/'powershell'
    waf=[p for p in (powershell/'WinAudioForensics.ps1',powershell/'WinAudioForensics.psm1') if p.exists()]
    if waf:
        bundle('cdl-winaudioforensics-powershell.zip',common+[(p,p.name) for p in waf])
    bash=ROOT/'bash'
    if bash.exists():
        bundle('cdl-audio-bash.zip',common+[(p,p.relative_to(ROOT).as_posix()) for p in bash.rglob('*') if p.is_file()])
    shell_ps=[p for p in powershell.rglob('*') if p.is_file() and not p.name.startswith('WinAudioForensics')]
    if shell_ps:
        bundle('cdl-audio-powershell.zip',common+[(p,p.relative_to(ROOT).as_posix()) for p in shell_ps])
    for folder in ('spec','docs'):
        target=ROOT/'site'/folder
        target.mkdir(exist_ok=True)
        for p in (ROOT/folder).glob('*.md'):shutil.copyfile(p,target/p.name)
if __name__=='__main__':main()
