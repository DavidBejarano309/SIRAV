"""Empaqueta la versión 3FN sin secretos, dependencias ni documentos anteriores."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import os

root = Path(__file__).resolve().parents[1]
output = root/'output'
output.mkdir(exist_ok=True)
excluded = {'.git','.tools','.runtime','node_modules','target','dist','coverage','test-results','playwright-report','__pycache__'}
files = []
for folder in ['backend','frontend','database','.github']:
    for directory, folders, names in os.walk(root/folder):
        folders[:] = [name for name in folders if name not in excluded]
        files.extend(Path(directory)/name for name in names if not name.endswith(('.zip','.log')) and name!='.env')
for name in ['README.md','.gitignore','.gitattributes','.env.example','compose.yaml','compose.test.yaml']:
    files.append(root/name)
for name in ['configure.ps1','configure.sh','start-local.ps1','start-local-api.ps1','init-local-db.ps1','test-local.ps1','backup.sh','generate-dictionary.py','export-project.py','generate-supuestos-matrix.py','measure-local.ps1','api-demo.http']:
    files.append(root/'scripts'/name)
for name in ['CAMBIOS-3FN.md','ARQUITECTURA.md','DICCIONARIO.md','MANUAL.md','MODELOS.md','PRUEBAS.md','REQUISITOS.md','GESTION.md','REFERENCIAS.md','SUPUESTOS-CUMPLIMIENTO.md','modelo-chen.dot']:
    files.append(root/'docs'/name)
files.append(root/'docs/referencias/01-schema-SIRAV-revisado-3FN.sql')
files.append(root/'docs/referencias/Supuestos_SIRAV.docx')
files.extend((root/'docs/evidencias').glob('supuestos-*'))
archive = output/'SIRAV-3FN-supuestos.zip'
with ZipFile(archive,'w',ZIP_DEFLATED) as package:
    for path in sorted(files):
        package.write(path,Path('SIRAV')/path.relative_to(root))
print(f'{archive}: {len(files)} archivos, {archive.stat().st_size:,} bytes')
