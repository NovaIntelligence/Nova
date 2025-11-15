package trivy.ignore

# Example (disabled) rule showing how to ignore specific config findings
# Do NOT enable without explicit approval.
#
# import future.keywords
#
# default deny = false
#
# deny {
#   input.Result.Class == "misconfig"
#   input.Result.Target == "docs/"
# }
