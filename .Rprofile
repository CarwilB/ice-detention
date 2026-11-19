source("renv/activate.R")
if (interactive()) {
  suppressMessages(require(targets))
  suppressMessages(require(dplyr))
  suppressMessages(require(stringr))
  suppressMessages(require(devtools))
  # The require() calls above attach dplyr before the base packages (stats,
  # graphics, ...), leaving dplyr below stats in the search path, so bare
  # filter() and lag() resolve to stats::. Detach and re-attach so dplyr
  # outranks the base packages, as in a normal session.
  if ("package:dplyr" %in% search()) suppressWarnings(detach("package:dplyr"))
  suppressMessages(library(dplyr))
}
