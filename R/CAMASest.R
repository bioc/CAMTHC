#' A and S matrix estimation by CAM
#'
#' This function estimates A and S matrix based on marker gene clusters detected by CAM.
#' @param data    Matrix of mixture expression profiles.
#'     Each row is a gene and each column is a sample.
#'     data should be in non-log linear space with non-negative numerical values (i.e. >= 0).
#'     Missing values are not supported.
#' @param PrepResult An object of class "CAMPrepObj" from \code{\link{CAMPrep}}.
#' @param MGResult An object of class "CAMMGObj" from \code{\link{CAMMGCluster}}.
#' @param corner.strategy The method to detect corner clusters.
#'     1: minimum margin error; 2: minimum reconstruction error.
#'     The default is 2.
#' @details This function is used internally by \code{\link{CAM}} function to
#' estimate proportion matrix (A), subpopulation-specific expression matrix (S)
#' and mdl values. It can also be used when you want to perfrom CAM step by step.
#'
#' mdl is calcluated in three approaches:
#'     (1) based on data and A in dimension-reduced space; (2) based on original data with A estimated
#'     by transforming dimension-reduced A back to original space;
#'     (3) based on original data with A directly estimated in origianl space.
#'     A and S matrix in origial space estiamted from the latter two approaches are returned.
#'     mdl is the sum of two terms: code length of data under the model and
#'     code length of model. Both mdl values and the first term (code length of data) will be returned.
#' @return An object of class "CAMASObj" containing the following components:
#' \item{Aest}{Estimated proportion matrix from Approach (2).}
#' \item{Sest}{Estimated subpopulation-specific expression matrix from Approach (2).}
#' \item{Aest.proj}{Estimated proportion matrix from Approach (2), before removing scale ambiguity.}
#' \item{Ascale}{The estimated scales to remove scale ambiguity
#'     of each column vector in Aest. Sum-to-one constraint on each row of
#'     Aest is used for scale estimation.}
#' \item{AestO}{Estimated proportion matrix from Approach (3).}
#' \item{SestO}{Estimated subpopulation-specific expression matrix from Approach (3).}
#' \item{AestO.proj}{Estimated proportion matrix from Approach (3), before removing scale ambiguity.}
#' \item{AscaleO}{The estimated scales to remove scale ambiguity
#'     of each column vector in AestO. Sum-to-one constraint on each row of
#'     AestO is used for scale estimation.}
#' \item{datalength}{Three values for code length of data. The first is calculated based on
#'     dimension-reduced data. The second and third are based on the original data.}
#' \item{mdl}{Three mdl values. The first is calculated based on
#'     dimension-reduced data. The second and third are based on the original data.}
#' @export
#' @examples
#' #obtain data
#' data(ratMix3)
#' data <- ratMix3$X
#'
#' #preprocess data
#' rPrep <- CAMPrep(data, thres.low = 0.30, thres.high = 0.95)
#'
#' #Marker gene cluster detection with a fixed K
#' rMGC <- CAMMGCluster(rPrep, K = 3, cores = 30)
#'
#' #A and S matrix estimation
#' rASest <- CAMASest(data, rPrep, rMGC)
CAMASest <- function(data, PrepResult, MGResult, corner.strategy = 2) {
    if (is.null(rownames(data))) {
        rownames(data) <- seq_len(nrow(data))
        warning('Gene/probe name is missing!')
    }
    X <- t(data)
    c.valid <- !(PrepResult$cluster$cluster %in% PrepResult$c.outlier)
    geneValid <- PrepResult$ValidIdx
    geneValid[geneValid][!c.valid] <- FALSE

    Xprep <- PrepResult$Xprep[,c.valid]
    Xproj <- PrepResult$Xproj[,c.valid]
    dataSize <- ncol(Xprep)

    Aproj <- PrepResult$centers[,as.character(MGResult$corner[corner.strategy,])]
    Kest <- ncol(Aproj)

    #scale <- as.vector(coef(nnls(Aproj, rowSums(PrepResult$W))))
    scale <- c(.fcnnls(Aproj, matrix(rowSums(PrepResult$W),ncol=1))$coef)
    Apca <- Aproj %*% diag(scale)
    #S1 <- apply(Xprep, 2, function(x) coef(nnls(Apca,x)))
    S1 <- .fcnnls(Apca, Xprep)$coef
    datalength1 <- (nrow(Xprep) * dataSize) / 2 * log(mean((as.vector(Xprep - Apca %*% S1))^2))
    penalty1 <- ((Kest - 1) * nrow(Xprep)) / 2 * log(dataSize) + (Kest * dataSize) / 2 * log(nrow(Xprep))
    mdl1 <- datalength1 + penalty1

    Aproj.org <- pseudoinverse(PrepResult$W) %*% Aproj
    #scale.org <- as.vector(coef(nnls(Aproj.org, matrix(1,nrow(Aproj.org),1))))
    scale.org <- c(.fcnnls(Aproj.org, matrix(1,nrow(Aproj.org),1))$coef)
    Aest.org <- Aproj.org%*%diag(scale.org)
    Aest.org[Aest.org < 0] <- 0
    Aest.org <- Aest.org/rowSums(Aest.org)
    #S2 <- apply(X, 2, function(x) coef(nnls(Aest.org, x)))
    S2 <- .fcnnls(Aest.org, X)$coef
    datalength2 <- (nrow(X) * dataSize) / 2 * log(mean((as.vector(X[,geneValid] - Aest.org %*% S2[,geneValid]))^2))
    penalty2 <- ((Kest - 1) * nrow(X)) / 2 * log(dataSize) + (Kest * dataSize) / 2 * log(nrow(X))
    mdl2 <- datalength2 + penalty2

    MGlist <- lapply(as.character(MGResult$corner[corner.strategy,]),
                     function(x) colnames(PrepResult$Xproj)[PrepResult$cluster$cluster == x])
    Xproj.all <- t(data/rowSums(data))
    Aproj.all <- matrix(0, ncol(data), length(MGlist))
    for(i in seq_along(MGlist)){
        Aproj.all[,i] <- pcaPP::l1median(t(Xproj.all[,MGlist[[i]]]))
    }
    #scale.all <- as.vector(coef(nnls(Aproj.all, matrix(1,nrow(Aproj.all),1))))
    scale.all <- c(.fcnnls(Aproj.all, matrix(1,nrow(Aproj.all),1))$coef)
    Aest.all <- Aproj.all%*%diag(scale.all)
    Aest.all <- Aest.all/rowSums(Aest.all)
    #S3 <- apply(X, 2, function(x) coef(nnls(Aest.all, x)))
    S3 <- .fcnnls(Aest.all, X)$coef
    datalength3 <- (nrow(X) * dataSize) / 2 * log(mean((as.vector(X[,geneValid] - Aest.all %*% S3[,geneValid]))^2))
    penalty3 <- penalty2
    mdl3 <- datalength3 + penalty3


    structure(list(Aest=Aest.org, Sest=t(S2), Aest.proj=Aproj.org, Ascale=scale.org,
                   AestO=Aest.all, SestO=t(S3), AestO.proj=Aproj.all, AscaleO=scale.all,
                   datalength=c(datalength1,datalength2,datalength3),mdl=c(mdl1,mdl2,mdl3)), class = "CAMASObj")
}