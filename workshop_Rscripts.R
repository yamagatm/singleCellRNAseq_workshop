###### - Input data and analysis tool requirements (setup)

library(Matrix)
library(Seurat)
library(dplyr)
library(SIMLR)


pbmc.data <- Read10X(data.dir = "~/Downloads/scRNAseqWS/10Xdata/filtered_gene_bc_matrices/GRCh38/")

pbmc <- CreateSeuratObject(raw.data = pbmc.data, min.cells = 3, min.genes = 200, project = "10X_PBMC")

mito.genes <- grep(pattern = "^MT-", x = rownames(x = pbmc@data), value = TRUE)

percent.mito <- Matrix::colSums(pbmc@raw.data[mito.genes, ])/Matrix::colSums(pbmc@raw.data)

pbmc <- AddMetaData(object = pbmc, metadata = percent.mito, col.name = "percent.mito")

head(pbmc@meta.data)

VlnPlot(pbmc, features.plot = c("nGene", "nUMI", "percent.mito"))

ggplot(pbmc@meta.data, aes(nUMI, nGene)) + geom_point()

ggplot(pbmc@meta.data, aes(nUMI, percent.mito)) + geom_point()

pbmc <- FilterCells(pbmc, subset.names = c("nGene", "percent.mito"), 
                    low.thresholds = c(200, -Inf), high.thresholds = c(2500, 0.05))

#Check to see if filtration works as we expected.
VlnPlot(pbmc, features.plot = c("nGene", "nUMI", "percent.mito"))

pbmc <- NormalizeData(pbmc, normalization.method = "LogNormalize", 
                      scale.factor = 10000)

pbmc <- FindVariableGenes(pbmc, mean.function = ExpMean, dispersion.function = LogVMR, 
                          do.plot = FALSE,display.progress = FALSE)

hv.genes <- head(rownames(pbmc@hvg.info), 1000)

pbmc <- ScaleData(pbmc, genes.use = hv.genes, vars.to.regress = c("nUMI", "percent.mito"),
                  display.progress = FALSE)
pbmc <- RunPCA(pbmc, pc.genes = hv.genes, do.print = FALSE)

PCAPlot(pbmc, dim.1 = 1, dim.2 = 2)

PCElbowPlot(pbmc)

pbmc <- FindClusters(pbmc, reduction.type = "pca", dims.use = 1:10, 
                     resolution = 0.6, print.output = TRUE, save.SNN = TRUE)
head(pbmc@ident,20)

pbmc <- RunTSNE(pbmc, dims.use = 1:10, do.fast = TRUE)

TSNEPlot(pbmc, do.label = TRUE)

pbmc.markers <- FindAllMarkers(pbmc, only.pos = TRUE, min.pct = 0.25, 
                               logfc.threshold = 0.25)

top5.markers <- pbmc.markers %>% group_by(cluster) %>% top_n(5, avg_logFC)

best.markers <- pbmc.markers %>% group_by(cluster) %>% top_n(1, avg_logFC)

FeaturePlot(object = pbmc, features.plot = best.markers$gene, cols.use = c("grey", "blue"), reduction.use = "tsne")

ob.list <- list("zeisel", "romanov", "tasic", "marques")

#Load the expression and meta data of each study.

for (i in 1:length(ob.list)){
  obj.data <- paste(ob.list[[i]],".data",sep=""); 
  #Read the expression matrix from a text file for each dataset.
  assign(obj.data, read.delim(paste("~/Downloads/scRNAseqWS/",ob.list[[i]],".expression.txt",sep=""), header = TRUE, row.names = 1))
}

#Since the expression matrices of these datasets are in TPM (already normalized), we are going to skip NormalizeData step in the following steps. However, we still need to log-transform it. log1p = log(1+x), natural log.
zeisel.data <- log1p(zeisel.data)
romanov.data <- log1p(romanov.data)
tasic.data <- log1p(tasic.data)
marques.data <- log1p(marques.data)

for (i in 1:length(ob.list)){
  obj.meta <- paste(ob.list[[i]],".meta",sep=""); 
  #Reading the Run information meta data from a text file for each dataset.
  assign(obj.meta, read.delim(paste("~/Downloads/scRNAseqWS/",ob.list[[i]],".RunTable.txt",sep=""), header = TRUE))
}
rownames(zeisel.meta) <- zeisel.meta$Run_s
rownames(romanov.meta) <- romanov.meta$Run_s
rownames(tasic.meta) <- tasic.meta$Run_s
rownames(marques.meta) <- marques.meta$Run_s

batches <- rbind(zeisel.meta[,c("Run_s","Owner","SRA_Study_s")],
                 tasic.meta[,c("Run_s","Owner","SRA_Study_s")],
                 romanov.meta[,c("Run_s","Owner","SRA_Study_s")],
                 marques.meta[,c("Run_s","Owner","SRA_Study_s")])

combined.data <- cbind(zeisel.data, tasic.data, romanov.data, marques.data)

combined.data <- as(as.matrix(combined.data), "dgCMatrix")

fourDataset <- CreateSeuratObject(raw.data = combined.data, project = "4dataset.Pre")

fourDataset <- AddMetaData(fourDataset, metadata = batches)

fourDataset <- FilterCells(fourDataset, subset.names = "nGene", low.thresholds = 2500)

fourDataset <- FindVariableGenes(fourDataset, do.plot = F, display.progress = F)

fourDataset <- ScaleData(fourDataset, display.progress = F)

fourDataset <- RunPCA(fourDataset, pc.genes = fourDataset@var.genes, pcs.compute = 10, do.print = FALSE)

PCAPlot(fourDataset, pt.size=1, group.by ="Owner", dim.1 = 1, dim.2 = 2)

fourDataset <- RunTSNE(fourDataset, reduction.use = "pca", dims.use = 1:10)

TSNEPlot(fourDataset, do.label = T, group.by ="Owner")

#Subset the data
zeisel <- SubsetData(fourDataset, cells.use=names(zeisel.data),do.center=T, do.scale=T)
tasic <- SubsetData(fourDataset, cells.use=names(tasic.data),do.center=T, do.scale=T)
romanov <- SubsetData(fourDataset, cells.use=names(romanov.data),do.center=T, do.scale=T)
marques <- SubsetData(fourDataset, cells.use=names(marques.data),do.center=T, do.scale=T)

ob.list <- list(zeisel, romanov, tasic, marques)

genes.use <- c()
for (i in 1:length(ob.list)) {
  genes.use <- c(genes.use, head(rownames(ob.list[[i]]@hvg.info), 1000))
}
genes.use <- names(which(table(genes.use) > 1))
for (i in 1:length(ob.list)) {
  genes.use <- genes.use[genes.use %in% rownames(ob.list[[i]]@scale.data)]
}

mouseBrain.integrated <- RunMultiCCA(ob.list, genes.use = genes.use, num.ccs = 15)

mouseBrain.integrated <- CalcVarExpRatio(mouseBrain.integrated, reduction.type = "pca",
                                         grouping.var = "Owner", dims.use = 1:10)

mouseBrain.integrated <- SubsetData(mouseBrain.integrated, subset.name = "var.ratio.pca",
                                    accept.low = 0.5)

mouseBrain.integrated <- AlignSubspace(mouseBrain.integrated,
                                       reduction.type = "cca",
                                       grouping.var = "Owner",
                                       dims.align = 1:10)

mouseBrain.integrated <- FindClusters(mouseBrain.integrated, reduction.type = "cca.aligned",
                                      dims.use = 1:10, save.SNN = T, resolution = 0.4)

mouseBrain.integrated <- RunTSNE(mouseBrain.integrated,
                                 reduction.use = "cca.aligned",
                                 dims.use = 1:10)

# Visualization
TSNEPlot(mouseBrain.integrated, do.label = T)

TSNEPlot(mouseBrain.integrated, do.label = T,group.by ="Owner")

#Alternative way of determining cell subset clusters

set.seed(11111)
# Determine optimal number of clusters as described in the Nat. Methods paper
# picka cluster range and reports two metrics; the lower the value the more
# support for that number of clusters; in my limited experience these methods
# are concordant.

zclust<-SIMLR_Estimate_Number_of_Clusters(zeisel.data, NUMC=2:5)

#run SIMLR
zsimlr<-SIMLR(zeisel.data, 4)

# Create plotting function, color-coding points by cluster membership
plotSIMLRclusters <- function(obj) {                                                                                                                                                           
  col <- ifelse(obj$y$cluster==1, 'red', ifelse(obj$y$cluster==2, 'blue',
                                                ifelse(obj$y$cluster==3, 'green','yellow')))    
  plot(obj$ydata, col=col, xlab = "SIMLR component 1", ylab = "SIMLR component 2", pch=20,  cex=0.7) 
}

# Call plotting function
plotSIMLRclusters(zsimlr)

sessionInfo()
