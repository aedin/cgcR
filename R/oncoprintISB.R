# define gene sets from cbioPortal

glioRTK = c(
"EGFR","ERBB2","PDGFRA","MET","KRAS","NRAS","HRAS","NF1","SPRY2","FOXO1","FOXO3","AKT1","AKT2","AKT3","PIK3R1","PIK3CA","PTEN"
)

pi3k = c(
"PIK3CA","PIK3R1","PIK3R2","PTEN","PDPK1","AKT1","AKT2","FOXO1","FOXO3","MTOR","RICTOR","TSC1","TSC2","RHEB","AKT1S1","RPTOR","MLST8"
)

ovtumsupp=c("DIRAS3","RASSF1","DLEC1","SPARC","DAB2","PLAGL1","RPS6KA2","PTEN","OPCML","BRCA2","ARL11","WWOX","TP53","DPH1","BRCA1","PEG3")

rasraf = c("KRAS","HRAS","BRAF","RAF1","MAP3K1","MAP3K2","MAP3K3","MAP3K4","MAP3K5","MAP2K1","MAP2K2","MAP2K3","MAP2K4","MAP2K5","MAPK1","MAPK3","MAPK4","MAPK6","MAPK7","MAPK8","MAPK9","MAPK12","MAPK14","DAB2","RASSF1","RAB25")

someSets = list(rasraf=rasraf, glioRTK=glioRTK,
   pi3k=pi3k,
   ovtumsupp = ovtumsupp)

attr(someSets, "fullTitle") = list(
   glioRTK="Glioblastoma: RTK/Ras/PI3K/AKT Signaling (17 genes)",
   pi3k="General: PI3K-AKT-mTOR signaling (17 genes)",
   ovtumsupp = "Ovarian Cancer: Putative tumor-suppressor genes in epithelial ovarian cancer (16 genes)",
   rasraf = "General: Ras-Raf-MEK-Erk/JNK signaling (26 genes)")

names(someSets) = unlist(attr(someSets, "fullTitle")[names(someSets)])
   
# some utilities for ISB bigquery content

isbTables = function(bq) {
# bq is a src_bigquery instance
  src_tbls(bq)
}

studiesInTable = function(bq, tabletag = "Somatic_Mutation_calls") {
  select = dplyr::select
  bq %>% tbl(tabletag) %>% select(Study) %>% group_by(Study) %>% summarise(nrec=n())
}

isbVarsInTable = function(bq, tabletag = "Somatic_Mutation_calls") {
  bq %>% tbl(tabletag) %>% tbl_vars()
}

.mutq <- function(studytag = "BRCA", limit=NULL) {
  ans = sub( "%%STUDYTAG%%", paste0("'", studytag, "'"), "SELECT COUNT (DISTINCT(pb)) AS sampleN, hugosymbols AS gene FROM ( SELECT ParticipantBarcode AS pb, Hugo_Symbol AS hugosymbols FROM [isb-cgc:tcga_201510_alpha.Somatic_Mutation_calls] WHERE Study = %%STUDYTAG%% GROUP BY hugosymbols, pb) GROUP BY gene ORDER BY sampleN DESC")
  if (!is.null(limit)) ans = paste0(ans, paste0(" LIMIT ", limit))
  ans
}

.genesWmutInStudyDFq = function(studytag="OV", limit=NULL) {
 # return data frame with columns sampleN, gene
 .mutq(studytag, limit)
}

.participantBarcodesInTableInStudyq = function(tabletag = "Somatic_Mutation_calls", studytag="OV", limit=NULL) {
  sub1 = sub( "%%STUDYTAG%%", paste0("'", studytag, "'"), "SELECT ParticipantBarcode FROM [isb-cgc:tcga_201510_alpha.%%TABLETAG%%] WHERE Study = %%STUDYTAG%% ")
  ans = sub("%%TABLETAG%%", tabletag, sub1 )
  if (!is.null(limit)) ans = paste0(ans, paste0(" LIMIT ", limit))
  ans
}


genesWmutInStudyDF = function(project, studytag="OV", limit=NULL)
  query_exec( .genesWmutInStudyDFq(studytag="OV", limit=NULL), project = project )

mutsInGeneInStudyDF = function(bq, gene = "KRAS", studytag = "LUAD") {
  select = dplyr::select
  bq %>% tbl("Somatic_Mutation_calls") %>% select(ParticipantBarcode, Hugo_Symbol,
         Variant_Classification, Study) %>% filter(Study == studytag) %>% 
             filter(Hugo_Symbol == gene) %>% as.data.frame()
  }
mutsInGenesInStudyDF = function(bq, genevec = c("KRAS", "HRAS"), studytag = "LUAD") {
  select = dplyr::select
  bq %>% tbl("Somatic_Mutation_calls") %>% select(ParticipantBarcode, Hugo_Symbol,
         Variant_Classification, Study) %>% filter(Study == studytag) %>% 
             filter(Hugo_Symbol %in% genevec) %>% as.data.frame()
  }
 
exprsByMutation = function( bq, gene = "GATA3", studytag = "BRCA", project, limit=NULL,
   dup.expr.action=function(x) 2^mean(log2(x)+1,na.rm=TRUE),
   substNAMut = "None" ) {
#
#  need to merge mutation data with expression data by participant bar code
#  alternate dup.expr.action could be to filter among the mutations reported
#
  select = dplyr::select
  if (missing(project)) stop("project must be supplied")
  ginstud = genesWmutInStudyDF( project, studytag=studytag, limit=limit ) # uses direct SQL
  stopifnot(gene %in% ginstud$gene)
  exprdata = bq %>% tbl("mRNA_UNC_HiSeq_RSEM") %>% select(ParticipantBarcode, HGNC_gene_symbol,
         normalized_count, Study) %>% filter(Study == studytag) %>% 
             filter(HGNC_gene_symbol == gene) %>% as.data.frame()
  mutdata = bq %>% tbl("Somatic_Mutation_calls") %>% select(ParticipantBarcode, Hugo_Symbol,
         Variant_Classification, Study) %>% filter(Study == studytag) %>% 
             filter(Hugo_Symbol == gene) %>% as.data.frame()
  mrg = merge(exprdata, mutdata, all.x=TRUE, by="ParticipantBarcode")
  hasdup = sum(duplicated(mrg$ParticipantBarcode))
  if (any(lkna <- is.na(mrg$Variant_Classification)))
     mrg$Variant_Classification[which(lkna)] = substNAMut
  if (hasdup==0) return(mrg)
  smrg = split(mrg, mrg$ParticipantBarcode)
  hasdup = which(sapply(smrg,nrow)>0)
  smrg[hasdup] = lapply(smrg[hasdup], function(x) { 
             tmp = dup.expr.action(x$normalized_count)
             fixd = x[1,,drop=FALSE]
             fixd$normalized_count = tmp
             fixd
             })
  do.call(rbind,smrg)
}

# very ad hoc support for oncoprint app

col = c("MIS"="blue", FRA="#008000", SPL="gold", "NONS"="red", "OTH"="pink")

alter_fun = list(
    background = function(x, y, w, h) {
        grid.rect(x, y, w-unit(0.5, "mm"), h-unit(0.5, "mm"), gp = gpar(fill = "#CCCCCC", col = NA))
    },
    MIS = function(x, y, w, h) {
        grid.rect(x, y, w-unit(0.5, "mm"), h-unit(0.5, "mm"), gp = gpar(fill = "blue", col = NA))
    },
    NONS = function(x, y, w, h) {
        grid.rect(x, y, w-unit(0.5, "mm"), h-unit(0.5, "mm"), gp = gpar(fill = "red", col = NA))
    },
    FRA = function(x, y, w, h) {
        grid.rect(x, y, w-unit(0.5, "mm"), h-unit(0.5, "mm"), gp = gpar(fill = "#008000", col = NA))
    },
    OTH = function(x, y, w, h) {
        grid.rect(x, y, w-unit(0.5, "mm"), h*0.33, gp = gpar(fill = "orange", col = NA))
    },
    SPL = function(x, y, w, h) {
        grid.rect(x, y, w-unit(0.5, "mm"), h-unit(0.5, "mm"), gp = gpar(fill = "gold", col = NA))
    }
)

# completely ad hoc management of mutation types here, must be
# pushed out to parameters

geneVecToOPInputByStudy = function(bq, genevec, studytag="LUAD") {
 jjj = mutsInGenesInStudyDF(bq, studytag=studytag, genevec=genevec)
 jjjs = split(jjj, jjj$Vari)
 jjjss = lapply(jjjs, function(x) split(x, x$Hugo_Symbol))
 types = names(jjjs)
 types= c("3'UTR", "Frame_Shift_Del", "Frame_Shift_Ins", "In_Frame_Del", 
 "In_Frame_Ins", "Intron", "Missense_Mutation", "Nonsense_Mutation", 
   "Silent", "Splice_Site")
 ttags = c("OTH;", "FRA;", "FRA;", "OTH;", "OTH;", "OTH;", "MIS;", "NONS;", "OTH;", "SPL;")
 names(ttags) = types
 targ = matrix("", nr=length(unique(jjj$Hugo_Symbol)), nc=length(unique(jjj$Particip)))
 rownames(targ) = unique(jjj$Hugo_Symbol)
 colnames(targ) = unique(jjj$Particip)
 for (i in names(jjjs)) {  # types
   for (j in names(jjjss[[i]])) { # genes 
       ini = targ[j, jjjss[[i]][[j]]$ParticipantBarcode] 
       targ[j, jjjss[[i]][[j]]$ParticipantBarcode] = paste(ini, rep(ttags[i], length(ini)), sep="")
       }
 }
 targ
}

library(shiny)

isbApp = function(bq) {
  gnsets = someSets
  studies = sort((studiesInTable(bq) %>% as.data.frame())[,1])
  ui = fluidPage(
    titlePanel("TCGA/ISB/bigQuery interface"),
    sidebarPanel(
     fluidRow(
      selectInput("study", "Tumor", choices=studies, selected="LUAD", selectize=TRUE),
      selectInput("geneset", "Gene set", choices=names(gnsets), selected=names(gnsets)[1], selectize=TRUE)
      )
     ), # end sidebar
    mainPanel(
     tabsetPanel(
      tabPanel("oncoPrint", plotOutput("onco")),
      tabPanel("genes", dataTableOutput("setelem"))
      )
    )
   )
  server = function(input, output) {
   output$onco = renderPlot({
      curstudy = input$study
      curset = gnsets[[input$geneset]]
      op = geneVecToOPInputByStudy(bq, curset, studytag=curstudy) 
      if (any(is.na(op))) op[is.na(op)] = "OTH;"
      if (any(op=="NA")) op[op=="NA"] = "OTH;"
      draw(oncoPrint(op, get_type = function(x) strsplit(x, ";")[[1]], alter_fun=alter_fun, col=col))
      #plot(1,1)
   })
   output$setelem = renderDataTable({
      curset = gnsets[[input$geneset]]
      mkln = function(x) gsub("%%GENE%%", x, "<a href='http://www.genecards.org/cgi-bin/carddisp.pl?gene=%%GENE%%&keywords=%%GENE%%'>%%GENE%%</a>")
      lns = sapply(curset, mkln)
#      anc = function(x) paste0("<a href=\"", x, "\">", x, "</a>")
#      lns = sapply(lns, anc)
      data.frame(HGNC=lns) #, card=lns)
      }, escape=FALSE)
   }
  shinyApp(ui, server)
} 
