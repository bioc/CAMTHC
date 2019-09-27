.onAttach <- function(libname, pkgname) {
    msg <- sprintf(
        "Package '%s' is deprecated and will be removed from Bioconductor
         version %s . Package renamed to debCAM",
        pkgname, "3.12")
    .Deprecated(msg=paste(strwrap(msg, exdent=2), collapse="\n"))
}
