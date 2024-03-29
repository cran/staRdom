#' Check for NAs in EEM data
#'
#' @param eem_list eemlist to check
#'
#' @return named character vector with sample names where EEM data contains NAs
#' @export
#'
#' @import dplyr
#' @import tidyr
#' @importFrom eemR eem_names
#' @importFrom stats setNames
#'
#' @examples
#' ### check
eem_is.na <- function(eem_list){
  lapply(eem_list,function(eem){
    sum(is.na(eem$x)| is.infinite(eem$x)) / length(eem$x)
  }) %>% unlist() %>%
    setNames(eem_names(eem_list))
}

#' Check size of EEMs
#'
#' @description The size of EEMs in an eemlist is checked and the sample names of samples with more data than the sample with the smallest range are returned.
#'
#' @param eem_list eemlist
#'
#' @import dplyr
#'
#' @return character vector
#' @export
#'
#' @examples
#' data(eem_list)
#' eem_checksize(eem_list)
eem_checksize <- function(eem_list){
  all_range <- eem_list %>% eem_getextreme()
  samples_range <- lapply(eem_list,function(eem) eem_getextreme(list(eem)))
  sample_nr <- lapply(samples_range, function(range) identical(range,all_range)) %>% unlist()
  eem_list %>% eem_names() %>% .[!sample_nr]
}


#' Check for duplicate sample names
#'
#' @param data eemlist or data.frame containing absorbance data
#'
#' @return named character vector with duplicate sample names
#' @export
#'
#' @import dplyr
#' @import tidyr
#' @importFrom eemR eem_names
#'
#' @examples
#' ### check
eem_duplicates <- function(data) UseMethod("eem_duplicates")

#' @rdname eem_duplicates
#' @export
eem_duplicates.default <- function(data){
  stop("data is not of a suitable format!")
}

#' @rdname eem_duplicates
#' @export
#' @import dplyr
#' @import tidyr
#' @importFrom eemR eem_names
eem_duplicates.eemlist <- function(data){
  dupls <- eem_names(data) %>%
    table() %>%
    data.frame() %>%
    filter(Freq > 1) %>%
    .[,1] %>%
    as.character()
}

#' @rdname eem_duplicates
#' @export
#' @import dplyr
#' @import tidyr
#' @importFrom eemR eem_names
eem_duplicates.data.frame <- function(data){
  dupls <- colnames(data) %>%
    table() %>%
    data.frame() %>%
    filter(Freq > 1) %>%
    .[,1] %>%
    as.character()

  dots <- colnames(data) %>%
    grep("\\.[0-9]*$",.,value=TRUE) %>%
    gsub("(.)(\\.[0-9]*$){1}","\\1",.) %>%
    lapply(function(str){
      as <- colnames(data) %>%
        grep(paste0("^",str),.,value=TRUE)
      if(length(as > 1)) as else NA
    }) %>%
    unlist()

  dupls <- dupls %>%
    c(.,dots) %>% .[!is.na(.)]
}


#' Check your EEM, absorption and metadata before processing
#'
#' @description The function tries to lead you to possible problems in your data.
#'
#' @param eem_list eemlist continaing EEM data.
#' @param absorbance data.frame containing absorbance data.
#' @param metadata optional data.frame containing metadata.
#' @param metacolumns character vector of columns that are checkt for complete data sets
#' @param correction logical, whether EEMs should be checked for applied corrections
#' @param error logical, whether a problem should cause an error or not.
#'
#' @return writes out possible porblems to command line, additionally list with sample names where possible problems were found, see details.
#' @export
#'
#' @details The returned list contains character vectors with sample names where possible problems were found: problem (logical, whether a severe problem was found), nas (sample names with NAs in EEM data), missing_correction (correction of EEM samples was not done or not done successfully),eem_no_abs (EEM samples with no absorbance data), abs_no_eem (samples with present absorbance but no EEM data), duplse (duplicate sample names in EEM data), duplsa (duplicate sample names in absorbance data), invalid_eem (invalid EEM sample name), invalid_abs (invalid absorbance sample name), range_mismatch (wavelength ranges of EEM and absorbance data are mismatching), metadupls (duplicate sample names in metadata), metamissing (EEM samples where metadata is missing), metaadd (samples in metadata without EEM data)
#'
#' @import dplyr
#' @import tidyr
#' @importFrom eemR eem_names eem_extract
#'
#' @examples
#' folder <- system.file("extdata/EEMs", package = "staRdom") # load example data
#' eem_list <- eem_read(folder, recursive = TRUE, import_function = eem_csv)
#'
#' abs_folder <- system.file("extdata/absorbance", package = "staRdom") # load example data
#' absorbance <- absorbance_read(abs_folder, cores = 2)
#'
#' metatable <- system.file("extdata/metatable_dreem.csv",package = "staRdom")
#' meta <- read.table(metatable, header = TRUE, sep = ",", dec = ".", row.names = 1)
#'
#' checked <- eem_checkdata(eem_list, absorbance, metadata = meta,
#' metacolumns = "dilution", error = FALSE)
#' # This example returns a message, that absorbance data for the
#' # blank samples are missing. As absorbance is supposed to be 0 over
#' # the whole spectrum when you measure blanks, there is no need
#' # to supply the data and do an inner-filter effect correction.
eem_checkdata <- function(eem_list,absorbance,metadata = NULL, metacolumns = NULL, correction = FALSE, error = TRUE){
  problem = FALSE

  nas <- eem_is.na(eem_list)
  if(any(nas > 0)){
    cat("NAs were found in the following samples (ratio): ",paste0(names(nas)," (",round(nas,2),")",collapse = "", sep=", "),fill=TRUE)
    if(any(nas > 0.12)){
      cat(paste0("One or more samples have a NA ratio of ",round(max(nas),2)," a meaningful PARAFAC model might be difficult to produce. We suggest to interpolate the data or using a very high number of starts."), fill = TRUE)
    } else {
      cat("Please consider interpolating the data. It is highly recommended, due to more stable and meaningful PARAFAC models!")
    }
    problem = TRUE
  }

  size_prob <- eem_checksize(eem_list)
  if(length(size_prob) > 0){
    cat("The following samples contain more EEM data than the smallest in the sample set:",paste0(size_prob,collapse = "", sep=", "),fill=TRUE)
    problem = TRUE
  }

if(correction){
  missing_correction <- lapply(c("is_blank_corrected","is_scatter_corrected","is_ife_corrected","is_raman_normalized") %>% `names<-`(.,.), function(cor){
    cat("", fill=TRUE)
    cat("samples missing \"", cor, "\"", fill=TRUE)
    lapply(eem_list,function(eem){
      if(!attr(eem,cor)){
        cat(eem$sample, fill=TRUE)
        eem$sample %>% invisible()
        }
    }) %>% unlist() %>% invisible()
  }) %>% invisible()
} else missing_correction <- NA

  eem_no_abs <- eem_names(eem_list)[!eem_names(eem_list) %in% colnames(absorbance)]
  if(length(eem_no_abs) > 0){
    cat(fill=TRUE)
    cat("EEM samples missing absorbance data:",fill=TRUE)
    lapply(eem_no_abs,function(dup){
      locs <- eem_list %>% eem_extract(dup, keep=TRUE, verbose=FALSE) %>%
        lapply(function(eem) eem$location)
      cat(dup,"in ",paste0(locs,collapse=", "), fill=TRUE)
    }) %>% invisible()
    problem = TRUE
  }

  abs_no_eem <- colnames(absorbance)[!colnames(absorbance) %in% eem_names(eem_list)] %>%
    .[. != "wavelength"]
  if(length(abs_no_eem) > 0){
    cat(fill=TRUE)
    cat("Absorbance data with missing EEM samples:",fill=TRUE)
    lapply(abs_no_eem,function(dup){
      locs <- attr(absorbance,"location")[which(colnames(absorbance) == dup) - 1]
      cat(dup,"in ",paste0(locs,collapse=", "), fill=TRUE)
    }) %>% invisible()
    cat("This can happen if you diluted for EEM and have additional undiluted absorbance samples.",fill=TRUE)
  }

  duplse <- eem_duplicates(eem_list)

  if(length(duplse) > 0) {
    cat(fill=TRUE)
    cat("Duplicate EEM sample names and according directories: ", fill=TRUE)
    lapply(duplse,function(dup){
      locs <- eem_list %>% eem_extract(dup, keep=TRUE, verbose=FALSE) %>%
        lapply(function(eem) eem$location)
      cat(dup,"in ",paste0(locs,collapse=", "), fill=TRUE)
    }) %>% invisible()
    problem = TRUE
  }

  duplsa <- eem_duplicates(absorbance)

  if(length(duplsa) > 0) {
    cat(fill=TRUE)
    cat("Duplicate absorbance sample names and according directories: ", fill=TRUE)
    lapply(duplsa,function(dup){
      locs <- attr(absorbance,"location")[which(colnames(absorbance) == dup) - 1]
      cat(dup,"in ",paste0(locs,collapse=", "), fill=TRUE)
    }) %>% invisible()
    cat("If sample names contain dots, please check if dots were in the original sample name or added by R due to duplicate sample names!")
  }

  invalid_eem <- eem_names(eem_list)[!eem_names(eem_list) %in% make.names(eem_names(eem_list))]
  if(length(invalid_eem) > 0) {
    cat(fill=TRUE)
    cat("Invalid sample names in EEM data:",fill=TRUE)
    lapply(invalid_eem,function(inv){
      locs <- eem_list %>% eem_extract(inv, keep=TRUE, verbose=FALSE) %>%
        lapply(function(eem) eem$location)
      cat(inv,"in ",paste0(locs,collapse=", "), fill=TRUE)
    }) %>% invisible()
    problem = TRUE
  }

  invalid_abs <- colnames(absorbance)[!colnames(absorbance) %in% make.names(colnames(absorbance))]
  if(length(invalid_abs) > 0){
    cat(fill=TRUE)
    cat("Invalid sample names in absorbance data:",fill=TRUE)
    lapply(invalid_abs,function(inv){
      locs <- attr(absorbance,"location")[which(colnames(absorbance) == inv) - 1]
      cat(inv,"in ",paste0(locs,collapse=", "), fill=TRUE)
    }) %>% invisible()
  }

  range_mismatch <- lapply(eem_list, function(eem){
    #eem <- eem_list[[1]]
    if(eem$sample %in% colnames(absorbance)){
      ar <- absorbance[c("wavelength",eem$sample)] %>%
        na.omit() %>%
        .$wavelength %>%
        range()
      er <- eem$em %>% range()
      if(er[1] < ar[1] | er[2] > ar[2]){
        cat(fill=TRUE)
        cat(eem$sample,": absorbance wavelength range is smaller than emission wavelength range, inner-filter effect correction is impossible!",fill=TRUE)
        problem <- TRUE
        return(eem$sample)
      }
    }
  }) %>% unlist(recursive = FALSE) %>%
    invisible()

  #metadata <- meta
  #metacolumns <- c("dilution")
  metadupls <- c()
  metamissing <- c()
  metaadd <- c()
  if(!is.null(metadata)){
    metadupls <- rownames(metadata) %>%
      table() %>%
      data.frame() %>%
      filter(Freq > 1) %>%
      .[,1] %>%
      as.character()
    if(length(metadupls) > 0) {
      cat(fill=TRUE)
      cat("The following sample names were duplicate in metadata:",paste0(metadupls,collapse=", "),fill=TRUE)
    }
    if(!is.null(metacolumns)){
      problem <- (lapply(metacolumns,function(col){
        problem <- FALSE
        if(col %in% colnames(metadata)){
          #col <- metacolumns[1]
          #col <- "dilution"
          #cat(col)
          #metadata[col] >= 0
          valid <- rownames(metadata)[metadata[col] >= 0]# %>%
          metamissing <- eem_names(eem_list)[!eem_names(eem_list) %in% valid]
          if(length(metamissing) > 0){
            cat(fill=TRUE)
            cat("Metadata column",col,"misses data for samples:",paste0(metamissing,collapse=", "),fill=TRUE)
            problem <- TRUE
          }
          metaadd <- valid[!valid %in% eem_names(eem_list)]
          if(length(metaadd) > 0){
            cat(fill=TRUE)
            cat("Metadata column",col,"contains additional data for samples with no EEM data present:",paste0(metaadd,collapse=", "),fill=TRUE)
          }
        } else cat("Column",col,"was not found in the table.", fill=TRUE)
        problem
      }) %>%
        unlist() %>%
        any()) | problem
    } else cat("No metadata was checked. No columns were supplied.",fill=TRUE)
  } else cat("No metadata was checked. Table was missing.",fill=TRUE)

  if(problem & error) stop("Please read the messages above carefully and correct the problems before continuing the analysis!")
  invisible(list(problem,nas,size_prob,missing_correction,eem_no_abs,abs_no_eem,duplse,duplsa,invalid_eem,invalid_abs,range_mismatch,metadupls,metamissing,metaadd) %>%
              setNames(c("Possible_problem_found","NAs_in_EEMs","EEMs_more_data_than_smallest","missing_data_correction","EEMs_missing_absorbance","Absorbance_missing_EEMs","Duplicate_EEM_names",
                         "Duplicate_absorbance_names","invalid_EEM_names","invalid_absorbance_names","EEM_absorbance_wavelength_range_mismatch","Duplicates_metatable_names","EEMs_missing_metadata","Metadata_missing_EEMs")))
}

#' Create table that contains sample names and locations of files.
#'
#' @description You can use this table as an overview of your files and/or as a template for creating a metadata table.
#'
#' @param eem_list eemlist
#' @param absorbance data frame with absorbance data
#'
#' @return data frame
#' @export
#'
#' @import dplyr
#' @import tidyr
#'
#' @examples
#' folder <- system.file("extdata/EEMs", package = "staRdom") # load example data
#' eem_list <- eem_read(folder, recursive = TRUE, import_function = eem_csv)
#' data(absorbance)
#'
#' eem_metatemplate(eem_list,absorbance)
eem_metatemplate <- function(eem_list = NULL, absorbance = NULL){
  if(!is.null(eem_list)){
    t1 <- data.frame(sample = eem_names(eem_list), eem_location = lapply(eem_list,function(eem) eem$location) %>% unlist(),stringsAsFactors = FALSE)
  }
  if(!is.null(absorbance)){
    loc <- attr(absorbance,"location")
    t2 <- data.frame(sample = colnames(absorbance) %>% .[. != "wavelength"], abs_location = ifelse(is.null(loc),NA,loc),stringsAsFactors = FALSE)
    if(exists("t1")) t1 <- full_join(t1,t2,by="sample") else t1 <- t2
  }
  t1
}


#' Return names of samples where certain corrections are missing.
#'
#' @param eem_list eemlist to be checked
#'
#' @return prints out sample names
#' @export
#'
#' @examples
#' data(eem_list)
#'
#' eem_corrections(eem_list)
eem_corrections <- function(eem_list){
  lapply(c("is_blank_corrected","is_scatter_corrected","is_ife_corrected","is_raman_normalized"), function(cor){
    cat("", fill=TRUE)
    cat(cor,"== FALSE", fill=TRUE)
    lapply(eem_list,function(eem){
      if(!attr(eem,cor)) cat(eem$sample, fill=TRUE)
    }) %>% invisible()
  }) %>% invisible()
}

#' Create table how samples should be corrected because of dilution
#'
#' @description Due to dilution absorbance spectra need to be multiplied by the dilution factor and names of EEM samples can be adjusted to be similar to their undiluted absorbance sample. The table contains information about these two steps. Undiluted samples are suggested by finding absorbance samples match the beginning of EEM sample name (see details).
#'
#' @param eem_list eemlist
#' @param abs_data absorbance data as data frame
#' @param dilution dilution data as data frame with rownames
#' @param auto way how to deal with dilution is chosen automatically. See details.
#' @param verbose print out more information
#'
#' @details If you choose an automatic analysis EEMs are renamed if there is only one matching undiluted absorbance sample. Matching samples is done by comparing the beginning of the sample name (e.g. "sample3_1to10" fits "sample3").
#'
#' @return data frame
#' @export
#'
#' @import dplyr
#' @import tidyr
#'
#' @examples
#' # no appropriate exmaple data available yet
#'
eem_dilcorr <- function(eem_list,abs_data,dilution, auto = FALSE, verbose = TRUE){
  if(verbose){
    warning("Please read carefully, this function needs some imput from you!\n", immediate. = TRUE)
    cat("Diluted absorbance can be treated either by replacing it with undiluted data from the same sample or by multiplying it with the dilution factor. Here you can choose which suggested undiluted sample you would like to use or if the multiplication with the dilution factor should be done.",fill=TRUE)
  }
  #dilution <- meta["dilution"]
  #auto <- TRUE
  ab <- lapply(eem_list,function(eem){
    #eem <- eem_list[[1]]
    #cat(eem$sample,fill=TRUE)
    if(dilution[eem$sample,] > 1){
      #abs <- grep(colnames(abs_data),eem$sample,value=TRUE)
      abs <- sapply(colnames(abs_data),function(pattern) grep(paste0("^",pattern),x=eem$sample,value=TRUE)) %>% unlist() %>% .[names(.) != eem$sample]
      #abs <- stringr::str_extract(colnames(abs_data),eem$sample) %>% na.omit()
      #abs <- colnames(abs_data)[grep(colnames(abs_data),eem$sample,value=TRUE)]
      if(length(abs) > 0) abstext <- sapply(1:length(abs), function(n) paste0("[",n,"]: ",names(abs)[n])) %>% unlist() else abstext <- NULL
      abstext <- c(abstext, paste0("[d]: multiply by factor ",dilution[eem$sample,], ", [blank]: do nothing > ")) %>%
        paste0(collapse=", ")
      #cat(abstext,fill=TRUE)
      if(!auto){
        if(verbose) cat(eem$sample,"was diluted and needs to be treated with in some way. Please choose an option and confirm with [enter]!",fill=TRUE)
        input <- readline(prompt = abstext)
      } else{
        if(length(abs) == 1) input <- "1" else input <- "d"
      }
      abs_factor <- NA
      abs_del <- NA
      eem_comment <- NA
      eem_newname <- NA
      if(input == "d"){
        abs_factor <- dilution[eem$sample,] %>% as.numeric()
        eem_comment <- paste0("diluted absorbance data multiplied by ",dilution[eem$sample,])
      } else if(input == ""){
        abs_factor <- 1
        eem_comment <- "diluted absorbance data not treated"
      } else if(input %in% 1:length(abs)){
        abs_factor <- 1
        abs_del <- eem$sample
        eem_comment <- paste0("original EEM sample: ",eem$sample)
        eem_newname <- abs[as.numeric(input)]
      } else{
        if(verbose) warning("The input '",input,"' for sample ",eem$sample, " could not be propperly interpreted!\n")
        eem_comment <- "error in combining diluted and undiluted sample data"
      }
      data.frame(eem_sample = eem$sample, abs_factor = abs_factor,abs_del = abs_del,eem_comment = eem_comment,
                 eem_newname = ifelse(is.null(names(eem_newname)),NA,names(eem_newname)), stringsAsFactors = FALSE)
    }else{
      data.frame(eem_sample = eem$sample, abs_factor = 1,abs_del = as.character(NA),eem_comment = "no dilution",eem_newname = as.character(NA), stringsAsFactors = FALSE)
    }
  }) %>%
    bind_rows() %>%
    `rownames<-`(eem_names(eem_list))

  undil_eem <- ab$eem_newname[ab$eem_newname %in% ab$eem_sample]
  if(length(undil_eem) > 0){
  if(auto){
    ab[ab$eem_sample %in% undil_eem,]$eem_newname <- "delete_eem"
  } else{
    cat("Some EEMs seem to have been measured in different dilutions. Please choose which to keep! Please check for duplicate sample names after running eem_eemdil.", fill = TRUE)
    del_eem <- lapply(undil_eem, function(x) {
      abstext <- paste0("Sample ",x,"seems to be measured in different dilutions, would you like to [d]elect the undiluted sample or [blank] do nothing?")
      input <- readline(prompt = abstext)
      if(input == "d") input <- "delete_eem" else input <- NA
    }) %>% unlist()
    ab[ab$eem_sample %in% undil_eem,]$eem_newname <- del_eem
  }
  }

  ab
}

#' Multiply absorbance data according to the dilution and remove absorbance from samples where undiluted data is used.
#'
#' @description According to dilution data absorbance is either multiplied by the according factor or the undiluted absorbance data is deleted. You can either specify the cor_data data table coming from \code{\link{eem_dilcorr}} or supply an eemlist, and the dilution data to created on the fly.
#'
#' @param abs_data absorbance data
#' @param eem_list optional eemlist
#' @param dilution optional dilution data as data frame
#' @param cor_data optional output from \code{\link{eem_dilcorr}} as data frame
#' @param auto optional, see \code{\link{eem_dilcorr}}
#' @param verbose optional, see \code{\link{eem_dilcorr}}
#'
#' @return data frame
#' @export
#'
#' @import dplyr
#' @import tidyr
#'
#' @examples
#' # no appropriate exmaple data available yet
#'
eem_absdil <- function(abs_data,eem_list = NULL,dilution = NULL, cor_data = NULL, auto = TRUE, verbose = FALSE){
  #cor_data <- dc
  if(is.null(cor_data)){
    if(!is.null(eem_list) & !is.null(dilution)){
      cor_data <- eem_dilcorr(eem_list,abs_data,dilution, auto = auto, verbose = verbose)
    } else {
      stop("You need to specify either cor_data or eem_list and dilution!")
    }
  }
  ad <- abs_data
  abs_factor <- cor_data %>%
    select(eem_sample, abs_factor) %>%
    filter(abs_factor > 1) #%>%
  #tibble::column_to_rownames("eem_sample")
  ad[abs_factor$eem_sample] <- as.data.frame(as.matrix(ad[abs_factor$eem_sample]) %*% diag(abs_factor$abs_factor))
  eem_sample <- cor_data$eem_newname %>% unlist() %>% na.omit()
  abs_del <- cor_data$abs_del %>% unlist() %>% na.omit() %>%
    .[!. %in% eem_sample]
  ad <- ad[!colnames(ad) %in% abs_del]
  ad
}

#' Correct names of EEM samples to match undiluted absorbance data.
#'
#' @param eem_list eemlist
#' @param abs_data optinal absorbance data as data frame
#' @param dilution optinal dilution data as data frame
#' @param cor_data optional output from \code{\link{eem_dilcorr}} as data frame
#' @param auto optional, see \code{\link{eem_dilcorr}}
#' @param verbose optional, see \code{\link{eem_dilcorr}}
#'
#' @return eemlist
#' @export
#'
#' @import dplyr
#' @import eemR
#'
#' @examples
#' # no appropriate exmaple data available yet
#'
eem_eemdil <- function(eem_list,abs_data = NULL, dilution = NULL, cor_data = NULL, auto = TRUE, verbose = FALSE){
  #cor_data <- dc
  if(is.null(cor_data)){
    if(!is.null(eem_list) | !is.null(dilution)){
      cor_data <- eem_dilcorr(eem_list,abs_data,dilution, auto = auto, verbose = verbose)
    } else {
      stop("You need to specify either cor_data or abs_data and dilution!")
    }
  }
  eel <- eem_list %>%
    eem_extract(paste0("^",cor_data[cor_data$eem_newname == "delete_eem",]$eem_sample %>% na.omit(),"$"))
  eem_sample <- cor_data$eem_newname %>% `names<-`(cor_data$eem_sample) %>% na.omit() %>% .[. != "delete_eem"]
  eel <- lapply(eel, function(eem){
    if(!is.na(eem_sample[eem$sample])) eem$sample <- eem_sample[eem$sample] %>% unname()
    eem
  }) %>%
    `class<-`("eemlist")
  eel
}
