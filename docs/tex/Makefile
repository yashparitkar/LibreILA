DATASHEET := datasheet
MANUAL := manual

LATEX := pdflatex -interaction=nonstopmode
BIBTEX := bibtex

.PHONY: all svg2pdf datasheet manual copy clean

all: svg2pdf datasheet manual copy clean

svg2pdf:
	for f in $$(find ./images -name '*.svg'); do \
		inkscape -D "$$f" -o "$${f%.svg}_converted.pdf"; \
	done

datasheet: svg2pdf
	-$(LATEX) $(DATASHEET).tex
	-$(BIBTEX) $(DATASHEET)
	-$(LATEX) $(DATASHEET).tex
	-$(LATEX) $(DATASHEET).tex

manual: svg2pdf
	-$(LATEX) $(MANUAL).tex
	-$(BIBTEX) $(MANUAL)
	-$(LATEX) $(MANUAL).tex
	-$(LATEX) $(MANUAL).tex

copy : 
	cp $(DATASHEET).pdf ../$(DATASHEET).pdf
	cp $(MANUAL).pdf ../$(MANUAL).pdf

# clean: the latex intermediates are found anywhere under here, the pdfs are
# named instead. Only the two documents, the subfile pdfs a standalone chapter
# or appendix build leaves behind and what svg2pdf wrote are generated, so a
# pdf figure dropped into images/ survives.
clean:
	find . -type f \( \
		-name '*.aux' -o -name '*.bbl' -o -name '*.blg' -o \
		-name '*.fdb_latexmk' -o -name '*.fls' -o -name '*.log' -o \
		-name '*.nav' -o -name '*.out' -o -name '*.snm' -o \
		-name '*.toc' -o -name '*.lof' -o -name '*.lot' -o \
		-name '*.synctex.gz' -o -name '*.vrb' -o -name '*.bcf' -o \
		-name '*.run.xml' \
	\) -delete
	rm -f $(DATASHEET).pdf $(MANUAL).pdf
	rm -f chapters/*.pdf appendices/*.pdf
	find ./images -name '*_converted.pdf' -delete
