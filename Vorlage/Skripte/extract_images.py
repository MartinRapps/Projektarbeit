import sys
sys.path.insert(0, './pymupdf_tmp')
import fitz

doc = fitz.open('Transactions in GIS - 2026 - Memduhoğlu - Machine Learning Classification of AI‐Generated and Human‐Mapped Buildings in.pdf')

for page_num in [12, 17]: # zero-based indices for approx pages 13, 18
    try:
        page = doc.load_page(page_num)
        images = page.get_images(full=True)
        if images:
            for img_index, img in enumerate(images):
                xref = img[0]
                base_image = doc.extract_image(xref)
                image_bytes = base_image["image"]
                image_ext = base_image["ext"]
                image_filename = f"LaTeX_Dateien/figure_page_{page_num+1}_{img_index}.{image_ext}"
                with open(image_filename, "wb") as image_file:
                    image_file.write(image_bytes)
                print(f"Saved {image_filename}")
    except Exception as e:
        print(f"Error on page {page_num}: {e}")
