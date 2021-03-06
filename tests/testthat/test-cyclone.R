# This checks the cyclone implementation against a reference R-based implementation.
# require(scran); require(testthat); source("test-cyclone.R")

classif.single <- function(cell, markers,Nmin.couples) { 
    test <- unlist(cell[markers[,1]]-cell[markers[,2]])
    tot <- sum(test!=0)
    if (tot < Nmin.couples){ return(NA) }  
    sum(test>0)/tot
}

random.success <- function(cell, markers, N, Nmin, Nmin.couples) {  
    cell.random <- .Call(scran:::cxx_auto_shuffle, cell, N)
    success <- apply(cell.random, 2, classif.single, markers=markers, Nmin.couples=Nmin.couples)
    success <- success[!is.na(success)]
    if (length(success) < Nmin) { return(NA) }
    
    test <- classif.single(cell,markers,Nmin.couples) 
    if (is.na(test)) { return(NA) } 
    mean(success<test)
}

refFUN <- function(x, pairs) {
    x <- as.matrix(x)
    storage.mode(x) <- "double"
    gene.names <- rownames(x)

    chosen.x <- list()
    for (p in names(pairs)) {
        curp <- pairs[[p]]
        m1 <- match(curp$first, gene.names)
        m2 <- match(curp$second, gene.names)
        keep <- !is.na(m1) & !is.na(m2)
        m1 <- m1[keep]
        m2 <- m2[keep]
        
        all.present <- sort(unique(c(m1, m2)))
        chosen.x[[p]] <- x[all.present,,drop=FALSE]
        pairs[[p]] <- data.frame(first=match(m1, all.present),
                                 second=match(m2, all.present))
    }

    N <- 1000L
    Nmin <- 100L
    Nmin.couples <- 50L
    score.G1<-apply(chosen.x$G1, 2, function(x) random.success(cell=x,markers=pairs$G1,N=N,Nmin=Nmin,Nmin.couples=Nmin.couples))#, genes.list=genes.list))
    score.S<-apply(chosen.x$S, 2, function(x) random.success(cell=x,markers=pairs$S,N=N, Nmin=Nmin, Nmin.couples=Nmin.couples))#,genes.list=genes.list))
    score.G2M<-apply(chosen.x$G2M, 2, function(x) random.success(cell=x,markers=pairs$G2M,N=N, Nmin=Nmin,Nmin.couples=Nmin.couples))#,genes.list=genes.list))

    scores <- data.frame(G1=score.G1, S=score.S, G2M=score.G2M) 
    scores.normalised<-data.frame(t(apply(scores, 1, function(x) (x)/sum(x))))

    phases <- rep("S", ncol(x))
    phases[score.G1 >= 0.5] <- "G1"
    phases[score.G2M >= 0.5 & score.G2M > score.G1] <- "G2M"

    return(list(phases=phases, scores=scores, normalized.scores=scores.normalised))
}

####################################################################################################

# get_proportion() does not work correctly on Windows 32 - reasons unknown.
skip_on_os("windows") 

# Spawning training data.

all.names <- paste0("X", seq_len(500))
Ngenes <- length(all.names)
all.pairs <- combn(Ngenes, 2)
re.pairs <- data.frame(first=all.names[all.pairs[1,]], second=all.names[all.pairs[2,]])

set.seed(100)
markers <- list(G1=re.pairs[sample(nrow(re.pairs), 100),],
                 S=re.pairs[sample(nrow(re.pairs), 200),],
               G2M=re.pairs[sample(nrow(re.pairs), 500),])

Ncells <- 10
test_that("cyclone works correctly on various datatypes", {
    # No ties.          
    set.seed(1000)
    X <- matrix(rnorm(Ngenes*Ncells), ncol=Ncells)
    rownames(X) <- all.names
    
    set.seed(100)
    reference <- refFUN(X, markers)
    set.seed(100)
    observed <- cyclone(X, markers)
    
    expect_identical(reference$phases, observed$phases)
    expect_equal(reference$scores, observed$scores)
    expect_equal(reference$normalized.scores, observed$normalized.scores)

    # Count data.
    set.seed(1001)
    X <- matrix(rpois(Ngenes*Ncells, lambda=10), ncol=Ncells)
    rownames(X) <- all.names
    
    set.seed(100)
    reference <- refFUN(X, markers)
    set.seed(100)
    observed <- cyclone(X, markers)
    
    expect_identical(reference$phases, observed$phases)
    expect_equal(reference$scores, observed$scores)
    expect_equal(reference$normalized.scores, observed$normalized.scores)

    # Low counts to induce more ties.
    set.seed(1002)
    X <- matrix(rpois(Ngenes*Ncells, lambda=1), ncol=Ncells)
    rownames(X) <- all.names
    
    set.seed(100)
    reference <- refFUN(X, markers)
    set.seed(100)
    observed <- cyclone(X, markers)
    
    expect_identical(reference$phases, observed$phases)
    expect_equal(reference$scores, observed$scores)
    expect_equal(reference$normalized.scores, observed$normalized.scores)
    
    # Changing the names of the marker sets.
    re.markers <- markers
    names(re.markers) <- paste0("X", names(markers))
    set.seed(100)
    re.out <- cyclone(X, re.markers)
    expect_identical(re.out$phase, character(0))
    expect_identical(colnames(re.out$scores), names(re.markers))
    expect_equal(unname(re.out$scores), unname(observed$scores))
})

# Checking that it also works with SCESet objects.

set.seed(1004)
X <- matrix(rpois(Ngenes*Ncells, lambda=100), ncol=Ncells)
rownames(X) <- all.names

test_that("Cyclone also works on SingleCellExperiment objects", {
    X2 <- SingleCellExperiment(list(counts=X))
    suppressWarnings(X2 <- normalize(X2))

    set.seed(100)
    reference <- refFUN(X, markers)
    
    set.seed(100)
    observed1 <- cyclone(X, markers)
    expect_equal(reference, observed1)
   
    # Doesn't matter whether you use the counts or logcounts. 
    set.seed(100)
    observed2 <- cyclone(X2, markers, assay.type="logcounts")
    expect_equal(reference, observed2)
})

test_that("cyclone behaves correctly without cells or markers", {
    # Sensible behaviour with no cells.
    out <- cyclone(X[,0], markers)
    expect_identical(out$phases, character(0))
    expect_identical(nrow(out$scores), 0L)
    expect_identical(colnames(out$scores), c("G1", "S", "G2M"))
    expect_identical(nrow(out$normalized.scores), 0L)
    expect_identical(colnames(out$normalized.scores), c("G1", "S", "G2M"))
    
    # Sensible behaviour with no markers.
    no.markers <- list(G1=re.pairs[0,],
                        S=re.pairs[0,],
                      G2M=re.pairs[0,])
    out <- cyclone(X, no.markers)
    expect_true(all(is.na(out$phases)))
    expect_identical(colnames(out$scores), c("G1", "S", "G2M"))
    expect_identical(nrow(out$scores), ncol(X))
    expect_true(all(is.na(out$scores)))
    expect_identical(colnames(out$normalized.scores), c("G1", "S", "G2M"))
    expect_identical(nrow(out$normalized.scores), ncol(X))
    expect_true(all(is.na(out$normalized.scores)))
})

