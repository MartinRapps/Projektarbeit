import re 
text = open('paper_text.txt', encoding='utf-8').read() 
pages = text.split('---PAGE ') 
for i in range(5, 12): 
    lines = pages[i].split('\n') 
    for l in lines: 
        if 'Table' in l or 'TABLE' in l or 'table' in l: 
            print(f'Page {i}:', l.strip()[:80]) 
