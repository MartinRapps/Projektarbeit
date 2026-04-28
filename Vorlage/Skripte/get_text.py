import re 
text = open('paper_text.txt', encoding='utf-8').read() 
pages = text.split('---PAGE ') 
print('PAGE 7:', pages[7][:200]) 
print('PAGE 8:', pages[8][:200]) 
print('PAGE 9:', pages[9][:200]) 
