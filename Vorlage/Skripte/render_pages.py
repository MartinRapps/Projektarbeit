import sys
sys.path.insert(0, './pymupdf_tmp')
import fitz

doc = fitz.open('Transactions in GIS - 2026 - Memduhoğlu - Machine Learning Classification of AI‐Generated and Human‐Mapped Buildings in.pdf')

for page_num in range(6, 12):
    page = doc.load_page(page_num)
    pix = page.get_pixmap(dpi=150)
    pix.save(f"LaTeX_Dateien/rendered_page_{page_num+1}.png")
    print(f"Rendered page {page_num+1}")
