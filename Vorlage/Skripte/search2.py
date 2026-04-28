import re
text = open('paper_text.txt', encoding='utf-8').read()
pages = text.split('---PAGE ')
terms = ['approximate 75:25', 'positive predictive value', 'ground truth', 'real-world', '6%']
for t in terms:
    for p in pages:
        if re.search(t, p, re.IGNORECASE):
            page_num = p.split('---')[0].strip()
            if page_num:
                print(f"Found '{t}' on page {page_num}")
