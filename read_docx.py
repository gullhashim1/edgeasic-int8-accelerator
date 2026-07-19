import zipfile
import xml.etree.ElementTree as ET

try:
    with zipfile.ZipFile('/home/hashim/projects/edgeasic-int8-accelerator/EdgeASIC_v4_8_32_Week_Implementation_and_Demo_Plan.docx') as docx:
        tree = ET.XML(docx.read('word/document.xml'))
        namespaces = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
        text_nodes = [node.text for node in tree.iterfind('.//w:t', namespaces) if node.text]
        content = ' '.join(text_nodes)
        
        # Format the text slightly by replacing "Week " with "\nWeek " to make it readable
        content = content.replace("Week", "\nWeek")
        print(content)
except Exception as e:
    print('Error:', e)
