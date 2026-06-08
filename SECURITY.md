# Security Policy

## Supported Versions

The Keep Platform is currently developed and supported from the `main` branch.

| Version                                      | Supported |
| -------------------------------------------- | --------- |
| `main`                                       | ✅         |
| older commits, forks, or local modifications | ❌         |

This project is not currently maintained as a versioned software release with long-term support branches.

## Reporting a Vulnerability

Please do not open a public GitHub issue for security vulnerabilities.

Report security concerns privately by emailing:

**[security@thekeepstudios.com](mailto:security@thekeepstudios.com)**

If that address is not yet configured, contact the repository maintainer directly until it is available.

When reporting a vulnerability, please include:

* A short description of the issue
* The affected file, service, or configuration
* Steps to reproduce, if safe
* The possible impact
* Any suggested fix, if known

## What To Report

Useful reports include:

* Exposed secrets, tokens, passwords, private keys, or kubeconfigs
* Insecure Kubernetes, Ansible, Helm, or GitOps configuration
* Public endpoint exposure issues
* Authentication or authorization bypasses
* Backup, logging, or monitoring data exposure
* CI/CD or deployment workflow risks

## What Not To Include

Please do not send real production secrets, private user data, database dumps, rescue/adopter/foster records, or animal medical records in a GitHub issue.

If sensitive proof is needed, describe the issue first and we will coordinate a safer way to review it.

## Response Expectations

The Keep Studios will make a good-faith effort to:

* Acknowledge reports within 5 business days
* Triage the issue based on severity and live infrastructure risk
* Fix or mitigate accepted vulnerabilities as practical
* Let the reporter know if the issue is accepted, declined, or needs more information

This is a small, self-hosted project, so response times may vary. Issues involving exposed secrets or live infrastructure risk will be prioritized.

## Responsible Disclosure

Please give us reasonable time to investigate and fix confirmed vulnerabilities before public disclosure.

Do not access, modify, delete, or exfiltrate data. Do not disrupt services. Do not use high-volume automated scanning against public services.
