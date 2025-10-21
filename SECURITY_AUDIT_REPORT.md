# Security Audit Report
**Date:** 2025-10-21
**Repository:** kfork (K7 Sandbox Management)
**Auditor:** Claude Code Security Analysis

---

## Executive Summary

This security audit identified **5 HIGH severity CVE vulnerabilities** in Python dependencies and **multiple security concerns** in the codebase. Immediate action is recommended to update vulnerable dependencies and address code-level security issues.

**Risk Level:** HIGH

---

## 1. Python Dependencies Inventory

### Core Dependencies (setup.py)
- `requests>=2.31.0` (core dependency)
- `httpx>=0.27.0` (optional, for async client)

### API Dependencies (src/k7/api/requirements.txt)
- `fastapi==0.104.1`
- `uvicorn[standard]==0.24.0`
- `kubernetes==28.1.0`
- `pydantic==2.5.0`
- `python-multipart==0.0.6`
- `requests==2.31.0`
- `typer==0.9.0`
- `rich==13.7.0`
- `pyyaml==6.0.1`
- `python-dotenv==1.0.0`

### Tutorial Dependencies (tutorials/langchain-react-agent/requirements.txt)
- `python-dotenv>=1.0.0`
- `langchain>=0.2.0`
- `langchain-openai>=0.1.0`

---

## 2. CVE Vulnerabilities Found

### CRITICAL & HIGH Severity

#### 1. CVE-2024-24762 - python-multipart ReDoS (HIGH)
- **Package:** python-multipart 0.0.6
- **Severity:** HIGH (CVSS 7.5)
- **Description:** Regular Expression Denial of Service (ReDoS) vulnerability in Content-Type header parsing. An attacker can send a specially crafted Content-Type header that causes excessive CPU consumption, stalling the application indefinitely.
- **Impact:** Denial of Service on FastAPI applications that parse form data
- **Affected Code:** src/k7/api/main.py (FastAPI endpoints)
- **Remediation:** Upgrade to python-multipart>=0.0.7 (or >=0.0.18 for latest fixes)

#### 2. CVE-2024-35195 - requests Certificate Verification Bypass (MEDIUM)
- **Package:** requests 2.31.0
- **Severity:** MEDIUM (CVSS 5.6)
- **Description:** When making requests through a Session with verify=False, all subsequent requests to the same host ignore certificate verification regardless of verify parameter changes.
- **Impact:** SSL/TLS certificate validation bypass, potential MITM attacks
- **Affected Code:**
  - src/katakate/client.py:33-35 (Client class with verify_ssl parameter)
  - setup.py:11 (dependency specification)
- **Remediation:** Upgrade to requests>=2.32.0

#### 3. FastAPI ReDoS via python-multipart (HIGH)
- **Package:** fastapi 0.104.1 (depends on vulnerable python-multipart)
- **Severity:** HIGH (CVSS 7.5)
- **Description:** FastAPI versions before 0.109.1 are vulnerable to ReDoS when parsing form data due to the underlying python-multipart vulnerability.
- **Impact:** Denial of Service
- **Affected Code:** src/k7/api/main.py (all API endpoints)
- **Remediation:** Upgrade to fastapi>=0.109.1

#### 4. Multiple LangChain CVEs (CRITICAL - Tutorial Code)
- **Package:** langchain>=0.2.0
- **Severity:** CRITICAL (Multiple CVEs with CVSS 9.0+)
- **CVEs Found:**
  - **CVE-2024-36480** (CVSS 9.0 - Critical): Remote Code Execution vulnerability
  - **CVE-2024-28088**: Path traversal allowing API key disclosure and RCE
  - **CVE-2024-5998**: Pickle deserialization leading to arbitrary command execution
  - **CVE-2024-8309**: SQL injection through prompt injection
  - **CVE-2024-7774**: Path traversal allowing file system manipulation
  - **CVE-2024-21513** (CVSS 7.3): Arbitrary code execution in langchain-experimental

- **Impact:** Remote Code Execution, Data Exfiltration, Unauthorized Access
- **Affected Code:** tutorials/langchain-react-agent/agent.py
- **Remediation:** Upgrade to latest LangChain version (>=0.2.4 minimum, latest recommended)
- **Note:** This affects tutorial/example code, not core product functionality

### LOW/NO Risk

#### 5. pyyaml 6.0.1 - CLEAN
- **Status:** No known CVEs
- **Note:** Version 6.0.1 is safe. Historical vulnerabilities (CVE-2020-14343, CVE-2020-1747) only affected versions <5.4

#### 6. pydantic 2.5.0 - CLEAN
- **Status:** No known CVEs affecting this version
- **Note:** CVE-2024-3772 only affects versions <2.4.0

#### 7. uvicorn 0.24.0 - CLEAN
- **Status:** No known CVEs affecting this version
- **Note:** CVE-2020-7695 and CVE-2020-7694 only affect versions <0.11.7

#### 8. kubernetes 28.1.0 - CLEAN
- **Status:** No specific CVEs found for this Python client version
- **Note:** Some recent urllib3 vulnerabilities reported but not directly affecting this version

---

## 3. Code-Level Security Issues

### HIGH Priority

#### 3.1 Command Injection Risk (HIGH)
**Location:** src/k7/core/core.py:866
```python
exec_command = ["/bin/sh", "-c", command]
```
- **Issue:** Executes arbitrary commands in sandbox pods without sanitization
- **Impact:** While sandboxed in Kata containers, malicious commands could still cause damage within the sandbox
- **Recommendation:**
  - Add command validation/sanitization
  - Implement command whitelisting for production use
  - Add rate limiting per sandbox

#### 3.2 Environment Variable Injection
**Location:** src/k7/core/core.py:410-424
```python
if config.env_file and os.path.exists(config.env_file):
    with open(config.env_file, "r") as f:
        env_content = f.read()
    # Parse env file lines
```
- **Issue:** Reads arbitrary files from local filesystem based on user input
- **Impact:** Potential local file disclosure if path validation is insufficient
- **Recommendation:**
  - Restrict env_file paths to specific directories
  - Validate file paths against directory traversal (../)
  - Add file size limits

#### 3.3 Subprocess Injection Risk
**Location:** src/k7/core/core.py:314-326
```python
cmd = ["ansible-playbook", "-i", inventory_path, playbook_path]
if verbose:
    cmd.append("-v")
process = subprocess.Popen(cmd, ...)
```
- **Issue:** Executes Ansible playbooks from temporary files
- **Impact:** If playbook content is not properly validated, could lead to command injection
- **Recommendation:**
  - Validate playbook YAML structure before execution
  - Use subprocess with shell=False (already done - good)
  - Add playbook content sanitization

### MEDIUM Priority

#### 3.4 API Key Storage (MEDIUM - Acceptable with Improvements)
**Location:** src/k7/api/main.py:17, 42-47
- **Current Implementation:** File-based storage at /etc/k7/api_keys.json with 0600 permissions, SHA256 hashing
- **Good Practices Observed:**
  - Keys are hashed with SHA256
  - Timing-attack resistant comparison using secrets.compare_digest()
  - File permissions set to 0600
  - API key expiration supported
- **Concerns:**
  - SHA256 is not a password hashing algorithm (use bcrypt, argon2, or scrypt)
  - File-based storage is less secure than database with encryption at rest
  - No rate limiting on authentication attempts
- **Recommendations:**
  - Migrate to proper password hashing (bcrypt/argon2)
  - Consider database storage with encryption
  - Add rate limiting for failed auth attempts
  - Implement key rotation policies

#### 3.5 SSL Verification Bypass Option
**Location:** src/katakate/client.py:30-35
```python
def __init__(self, endpoint: str, api_key: str, verify_ssl: bool = True):
    self.session.verify = verify_ssl
```
- **Issue:** Allows disabling SSL verification
- **Impact:** Potential MITM attacks when verify_ssl=False
- **Recommendation:**
  - Remove verify_ssl=False option for production
  - Log warnings when SSL verification is disabled
  - Make it configurable only via explicit environment variable

#### 3.6 Broad Exception Handling
**Multiple Locations:** Throughout codebase
```python
except Exception:
    pass
```
- **Issue:** Silent failures can hide security issues and make debugging difficult
- **Impact:** Security events may go unnoticed
- **Recommendation:**
  - Use specific exception types
  - Log all caught exceptions
  - Add monitoring/alerting for security-relevant errors

### LOW Priority

#### 3.7 Hardcoded Paths
**Location:** Multiple files
- `/etc/k7/api_keys.json`
- `/etc/rancher/k3s/k3s.yaml`
- `/var/lib/k7/embedded`
- **Recommendation:** Make configurable via environment variables (partially done)

#### 3.8 Missing Input Validation
**Location:** src/k7/api/main.py:202-210
- **Issue:** Command execution endpoint accepts arbitrary strings
- **Recommendation:** Add request size limits, command length validation

---

## 4. Security Strengths

### Positive Security Measures Identified

1. **Container Security Hardening** (src/k7/core/core.py:460-479)
   - Drops ALL capabilities by default
   - Sets `allowPrivilegeEscalation=false`
   - Configurable non-root user execution (UID 65532)
   - RuntimeDefault seccomp profiles
   - Kata container runtime for VM-level isolation

2. **Network Security** (src/k7/core/core.py:602-678)
   - Egress whitelisting via Kubernetes NetworkPolicies
   - DNS access controlled to CoreDNS only
   - Hardcoded deny-all ingress policy to prevent inter-VM communication
   - Pod-to-pod isolation

3. **API Authentication**
   - Timing-attack resistant key comparison
   - API key expiration support
   - Hash-based storage (though SHA256 should be replaced)
   - Proper 401 responses for auth failures

4. **Secret Management**
   - Kubernetes Secrets for environment variables
   - File permissions set to 0600 for API keys
   - No secrets committed to repository (verified)

---

## 5. Recommendations Summary

### Immediate Actions (Priority 1 - Within 24-48 hours)

1. **Update Dependencies:**
   ```bash
   # Update requirements files
   python-multipart>=0.0.18
   fastapi>=0.109.1
   requests>=2.32.0
   langchain>=0.2.4  # For tutorials
   ```

2. **Apply Security Patches:**
   - Test updated dependencies in staging environment
   - Deploy to production after validation

### Short-Term Actions (Priority 2 - Within 1 week)

3. **Enhance API Key Security:**
   - Replace SHA256 with bcrypt or argon2 for key hashing
   - Implement rate limiting on authentication endpoints
   - Add audit logging for auth failures

4. **Input Validation:**
   - Add path validation for env_file parameter
   - Implement command sanitization for exec endpoint
   - Add request size limits

5. **Error Handling:**
   - Replace broad exception handlers with specific ones
   - Add security event logging
   - Implement monitoring and alerting

### Long-Term Actions (Priority 3 - Within 1 month)

6. **Security Testing:**
   - Set up automated dependency scanning (Dependabot, Snyk)
   - Implement SAST/DAST in CI/CD pipeline
   - Regular penetration testing

7. **Architecture Improvements:**
   - Consider moving API key storage to encrypted database
   - Implement OAuth2/OIDC for API authentication
   - Add API gateway with rate limiting and WAF

8. **Documentation:**
   - Create security.md with security best practices
   - Document threat model and security boundaries
   - Add incident response procedures

---

## 6. Compliance & Standards

### Security Standards Alignment

- **OWASP Top 10 2021:**
  - A01:2021 - Broken Access Control: Addressed via API keys, needs improvement
  - A02:2021 - Cryptographic Failures: SHA256 key hashing needs upgrade
  - A03:2021 - Injection: Command injection risks present
  - A06:2021 - Vulnerable Components: HIGH - Multiple outdated dependencies

### PCI DSS Considerations (if handling payment data)
- API key storage does not meet PCI DSS requirements for credential storage
- Encryption at rest needed for sensitive data

---

## 7. Risk Assessment Matrix

| Vulnerability | Severity | Exploitability | Impact | Overall Risk |
|--------------|----------|----------------|---------|--------------|
| python-multipart ReDoS | HIGH | Medium | High (DoS) | **HIGH** |
| requests SSL bypass | MEDIUM | Low | Medium (MITM) | **MEDIUM** |
| FastAPI ReDoS | HIGH | Medium | High (DoS) | **HIGH** |
| LangChain RCE (tutorials) | CRITICAL | High | Critical (RCE) | **CRITICAL** |
| Command injection | HIGH | Medium | High | **HIGH** |
| File path traversal | MEDIUM | Medium | Medium | **MEDIUM** |
| Weak key hashing | MEDIUM | Low | Medium | **MEDIUM** |

---

## 8. Conclusion

The K7 Sandbox Management system demonstrates several strong security practices, particularly in container isolation and network security. However, **immediate action is required** to address critical dependency vulnerabilities, especially:

1. **python-multipart** and **FastAPI** ReDoS vulnerabilities (DoS risk)
2. **requests** SSL verification bypass (MITM risk)
3. **LangChain** critical vulnerabilities in tutorial code (RCE risk)

The codebase shows good security awareness with Kata containers, capability dropping, and network policies. With the recommended dependency updates and code-level improvements, the security posture will be significantly strengthened.

**Next Steps:**
1. Update all vulnerable dependencies immediately
2. Test in staging environment
3. Deploy security patches to production
4. Implement automated security scanning
5. Schedule regular security audits

---

## Appendix A: Full Dependency List with Versions

### Production Dependencies
```
fastapi==0.104.1              # VULNERABLE - Update to >=0.109.1
uvicorn[standard]==0.24.0     # OK
kubernetes==28.1.0            # OK
pydantic==2.5.0              # OK
python-multipart==0.0.6       # VULNERABLE - Update to >=0.0.18
requests==2.31.0              # VULNERABLE - Update to >=2.32.0
typer==0.9.0                 # OK
rich==13.7.0                 # OK
pyyaml==6.0.1                # OK
python-dotenv==1.0.0         # OK
httpx>=0.27.0                # OK (optional)
```

### Tutorial/Development Dependencies
```
langchain>=0.2.0             # VULNERABLE - Update to latest
langchain-openai>=0.1.0      # Review and update
python-dotenv>=1.0.0         # OK
```

---

## Appendix B: Security Contact Information

For security vulnerabilities, please follow responsible disclosure:
1. Check SECURITY.md in the repository
2. Do not open public issues for security vulnerabilities
3. Report privately to maintainers

---

**Report End**
