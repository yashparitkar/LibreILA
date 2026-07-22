DATASHEET := datasheet
MANUAL := manual

LATEX := pdflatex -interaction=nonstopmode
BIBTEX := bibtex

.PHONY: all datasheet manual copy clean

all: all datasheet manual copy clean

datasheet:
	-$(LATEX) $(DATASHEET).tex
	-$(BIBTEX) $(DATASHEET)
	-$(LATEX) $(DATASHEET).tex
	-$(LATEX) $(DATASHEET).tex

datasheet:
	-$(LATEX) $(MANUAL).tex
	-$(BIBTEX) $(MANUAL)
	-$(LATEX) $(MANUAL).tex
	-$(LATEX) $(MANUAL).tex

copy : 
	cp $(DATASHEET).pdf ../$(DATASHEET).pdf
	cp $(MANUAL).pdf ../$(MANUAL).pdf

clean:
	find . -type f \( \
		-name '*.aux' -o -name '*.bbl' -o -name '*.blg' -o \
		-name '*.fdb_latexmk' -o -name '*.fls' -o -name '*.log' -o \
		-name '*.nav' -o -name '*.out' -o -name '*.snm' -o \
		-name '*.toc' -o -name '*.lof' -o -name '*.lot' -o \
		-name '*.synctex.gz' -o -name '*.vrb' -o -name '*.bcf' -o \
		-name '*.run.xml' \
		-name '*.pdf' \
	\) -delete
	rm -f Chapters/*.pdf Appendices/*.pdf
