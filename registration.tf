# Optional self-registration, so onboarding completes in one apply. A create-time
# terraform_data + local-exec rather than an http data source, which would re-run
# on every plan. The endpoint accepts a repeat for the organization a secret is bound to.

resource "terraform_data" "register" {
  count = var.enable_self_registration ? 1 : 0

  # Every body field is a trigger by construction, so a changed value re-sends the
  # PUT. The secret is never a trigger: triggers_replace is persisted to state.
  triggers_replace = merge(local.registration_fields, {
    endpoint        = local.registration_endpoint
    organization_id = local.organization_id
  })

  # Shell-safe by construction, and this roster is what a new body field must be
  # audited against: endpoint, active_regions, region and data_account_id by
  # variable validation; readonly_role_name is a constant; the org and management
  # account ids are AWS-issued (org id also checked below). The secret arrives only
  # through the environment, never the command string.
  provisioner "local-exec" {
    environment = {
      BORIS_CONNECTION_SECRET = var.connection_secret
    }

    command = <<-EOT
      url="${local.registration_endpoint}/aws/install/${local.organization_id}"
      body='${local.registration_body}'
      for delay in 0 15 30 30 60 60 60; do
        if [ "$delay" -gt 0 ]; then sleep "$delay"; fi

        resp=$(curl -sS -w '\n%%{http_code}' --connect-timeout 10 --max-time 60 \
          -X PUT "$url" \
          -H 'Content-Type: application/json' \
          -H "Authorization: Bearer $BORIS_CONNECTION_SECRET" \
          -d "$body") || true
        code=$(printf '%s\n' "$resp" | tail -n 1)
        message=$(printf '%s\n' "$resp" | sed '$d')

        case "$code" in
          2??)
            exit 0
            ;;
          401)
            echo "B.O.R.I.S: registration was refused: the connection secret was not accepted." >&2
            echo "B.O.R.I.S: this does not clear by retrying. Ask the B.O.R.I.S team to re-issue it." >&2
            exit 1
            ;;
          409)
            echo "B.O.R.I.S: registration was refused: $message" >&2
            echo "B.O.R.I.S: this does not clear by retrying — contact the B.O.R.I.S team." >&2
            exit 1
            ;;
          4??)
            echo "B.O.R.I.S: registration was rejected (HTTP $code): $message" >&2
            echo "B.O.R.I.S: this does not clear by retrying. Check the module inputs, then contact the B.O.R.I.S team." >&2
            exit 1
            ;;
          *)
            # $${code:-...} is a shell default; an empty code means curl is not on PATH.
            echo "B.O.R.I.S: registration attempt failed (HTTP $${code:-no response}); retrying" >&2
            ;;
        esac
      done
      echo "B.O.R.I.S: registration failed after retries. Verify the module applied cleanly, then re-run 'terraform apply', or register manually with the registration_curl output." >&2
      exit 1
    EOT
  }

  lifecycle {
    precondition {
      condition     = can(regex("^o-[a-z0-9]{10,32}$", local.organization_id))
      error_message = "The organization ID ${local.organization_id} is not of the form o-abc1234567."
    }
  }

  # Registers only once every role and StackSet the stack declares exists.
  depends_on = [aws_cloudformation_stack.boris_ai]
}
