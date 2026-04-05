# Web - {{URL}}

## Fingerprint

| Item        | Value |
|-------------|-------|
| Server      |       |
| Technology  |       |
| Framework   |       |
| CMS         |       |
| WAF         |       |

## Content Discovery

```bash
ffuf -u {{URL}}/FUZZ -w /usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt -o scans/ffuf.json
gobuster dir -u {{URL}} -w /usr/share/wordlists/dirb/common.txt
```

- [ ] Directory brute
- [ ] File extension brute
- [ ] Virtual host enumeration
- [ ] robots.txt / sitemap.xml

## Vulnerabilities

- [ ] SQLi
- [ ] XSS
- [ ] SSRF
- [ ] LFI / RFI
- [ ] File upload
- [ ] Auth bypass
- [ ] IDOR
- [ ] Deserialization

## Interesting Endpoints

| Path | Method | Notes |
|------|--------|-------|
|      |        |       |

## Notes
