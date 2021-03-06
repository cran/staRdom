% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/data_functions.R
\name{eem_range}
\alias{eem_range}
\title{Cut EEM data matching a given wavelength range}
\usage{
eem_range(data, ex = c(0, Inf), em = c(0, Inf))
}
\arguments{
\item{data}{EEM data as eemlist}

\item{ex}{optional desired range of excitation wavelength}

\item{em}{optional desired range of emission wavelength}
}
\value{
An eemlist of reduced spectra size.
}
\description{
Cut EEM data matching a given wavelength range
}
\examples{
data(eem_list)
eem_range(eem_list,ex = c(250,Inf),em = c(280,500))
}
