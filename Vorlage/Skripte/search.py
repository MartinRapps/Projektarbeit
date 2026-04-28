import re 
text = open('paper_text.txt', encoding='utf-8').read() 
pages = text.split('---PAGE ') 
terms = ['Table 1', 'Table 2', 'Table 3', 'Table 4'] 
for t in terms: 
    for p in pages: 
        if re.search(t, p, re.IGNORECASE): 
            page_num = p.split('---')[0].strip() 
            if page_num: 
