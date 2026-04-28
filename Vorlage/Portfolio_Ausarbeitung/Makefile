#################################################################################
##
## Makefile for LaTeX documents
##
## usage:
##    all   - to make all images and the whole thesis
##    clean - to clean all directories
##
#################################################################################
.PHONY: all clean publish makepdf makehtml
.SUFFIXES: .pdf .ps .dvi .eps .tex .html

#################################################################################
## file names
#################################################################################
FILE        = thesis
BIBTEXDB    = literatur.bib
TEXSRC      = $(FILE).tex
FILEPDF     = $(FILE).pdf
FILEAPDF    = $(FILE)-anonymous.pdf
FILEBPDF    = $(FILE)-withauthorname.pdf

#################################################################################
## programs etc.
#################################################################################
PDFLATEX    = pdflatex
PDFAOPT      = "\input{$(TEXSRC)}"
PDFBOPT      = "\def\iswithfullname{1} \input{$(TEXSRC)}"
BIBTEX      = biber
BIBOPT      = --min-crossrefs=99

#################################################################################
## make the document
#################################################################################
all: makepdf

makepdf: $(FILEAPDF) $(FILEBPDF)

$(FILEBPDF): $(TEXSRC) $(BIBTEXDB)
	$(PDFLATEX) $(PDFBOPT) && $(BIBTEX) $(FILE) && $(PDFLATEX) $(PDFBOPT) && $(PDFLATEX) $(PDFBOPT)
	mv $(FILEPDF) $(FILEBPDF)

$(FILEAPDF): $(TEXSRC) $(BIBTEXDB)
	$(PDFLATEX) $(PDFAOPT) && $(BIBTEX) $(FILE) && $(PDFLATEX) $(PDFAOPT) && $(PDFLATEX) $(PDFAOPT)
	mv $(FILEPDF) $(FILEAPDF)


#################################################################################
## clean all directories
#################################################################################
clean:
	$(RM) *.aux *.dvi *.ps *.pdf *.bbl *.log *.toc *~
	$(RM) *.blg *.lot *.out *.brf *.lof *.tps
	$(RM) *.run.xml *.lol *.bcf *-blx.bib
	$(RM) $(FILEPDF) $(FILEAPDF) $(FILEBPDF)
