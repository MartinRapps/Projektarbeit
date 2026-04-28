import sys 
sys.path.insert(0, './pypdf2_tmp') 
import PyPDF2 
filename = 'Transactions in GIS - 2026 - Memduhoğlu - Machine Learning Classification of AI‐Generated and Human‐Mapped Buildings in.pdf' 
with open(filename, 'rb') as f: 
    reader = PyPDF2.PdfReader(f) 
    with open('paper_text.txt', 'w', encoding='utf-8') as out: 
        for i, page in enumerate(reader.pages): 
            out.write(f'\n\n---PAGE {i+1}---\n\n') 
            out.write(page.extract_text() or '') 
