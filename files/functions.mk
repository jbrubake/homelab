# Characters that are hard to print {{{1
#
# Usage:
#   $(info $(nl))
#   $(info $,)
define nl


endef
, := ,

# Color configuration {{{1
#
COLOR ?= true
# if COLOR == true|yes|1
ifneq (,$(filter $(COLOR),true yes y 1))
    clr_err = [38;5;196m
    clr_wrn = [38;5;226m
    clr_msg = [38;5;50m
    clr_prn = [38;5;40m
    clr_rst = [0m
# elif COLOR == false|no|0
else ifneq (,$(filter $(COLOR),false no n 0))
    # Nothing needed
else
    $(error Unknown setting: COLOR=$(COLOR))
endif

# Message functions {{{1
#

die  = $(error   $(clr_err)$1$(clr_rst))
warn = $(warning $(clr_wrn)$1$(clr_rst))

# Print a message if VERBOSE >= 1
#
# Parameters:
#   1: message to print
#   2: 0 = no color, 1 = color (default)
define msg
	$(if $(filter 0,$(VERBOSE)),,@printf "$(if $(filter 1,$2),$(clr_msg))%s$(clr_rst)\n" "$1";)
endef

# Check for required binaries {{{1
#
# Parameters:
#   1: a list of binaries to check for
define check_for
    $(foreach b,$1,\
        $(if $(shell type -p $($b)),,\
	    $(call die,$($b) ($b) not found in PATH)))
endef

# Test if a string is an absolute path
#
# Call as:
#   $(call is_absolute,PATH)
#
is_absolute = $(if $(patsubst /%,,$1),,y)

