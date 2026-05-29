import base64, os, zipfile
from xml.etree import ElementTree as ET
b64 = os.environ['DOCX_B64']
path = base64.b64decode(b64).decode('utf-8')
with zipfile.ZipFile(path) as zf:
    data = zf.read('word/document.xml')
root = ET.fromstring(data)
ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
paragraphs = []
for p in root.findall('.//w:p', ns):
    parts = []
    for node in p.iter():
        if node.tag == '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}t' and node.text:
            parts.append(node.text)
        elif node.tag == '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}br':
            parts.append('\n')
    text = ''.join(parts).strip()
    if text:
        paragraphs.append(text)
print('\n'.join(paragraphs))
