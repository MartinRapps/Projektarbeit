import PyPDF2
import os

pdf_dir = '.'
for filename in os.listdir(pdf_dir):
    if filename.endswith('.pdf'):
        txt_filename = filename + '.txt'
        with open(filename, 'rb') as pdf_file, open(txt_filename, 'w', encoding='utf-8') as txt_file:
            reader = PyPDF2.PdfReader(pdf_file)
            for page in reader.pages:
                text = page.extract_text()
                if text:
                    txt_file.write(text + '\n')
print("Done extracting")
