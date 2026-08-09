SHELL := /bin/zsh
CONFIGURATION ?= release
APP_VARIANT ?=
SWIFT ?= swift
SECURITY ?= security
CODESIGN ?= codesign
CODESIGN_IDENTITY ?= Drift
LOCAL_CERTIFICATE_IDENTITY ?= Drift
SPARKLE_KEYCHAIN_SERVICE ?= https://sparkle-project.org
SPARKLE_ACCOUNT ?= com.woosublee.drift.sparkle.ed25519
SPARKLE_GENERATE_KEYS ?= .build/artifacts/sparkle/Sparkle/bin/generate_keys
SPARKLE_FEED_URL ?=
SPARKLE_PUBLIC_ED_KEY ?=
BUILD_DIR ?= /tmp/drift-bundles/default
IDENTITY_RESOLVER := scripts/resolve-build-identity.sh
RESOLVED_APP_VARIANT = $(shell $(IDENTITY_RESOLVER) "$(CONFIGURATION)" "$(APP_VARIANT)" variant)
PRODUCT_NAME = $(shell $(IDENTITY_RESOLVER) "$(CONFIGURATION)" "$(APP_VARIANT)" product-name)
BUNDLE_IDENTIFIER = $(shell $(IDENTITY_RESOLVER) "$(CONFIGURATION)" "$(APP_VARIANT)" bundle-id)
ACCESSIBILITY_DESCRIPTION = $(shell $(IDENTITY_RESOLVER) "$(CONFIGURATION)" "$(APP_VARIANT)" accessibility-description)
APP_DIR = $(BUILD_DIR)/$(PRODUCT_NAME).app
CONTENTS_DIR = $(APP_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
FRAMEWORKS_DIR = $(CONTENTS_DIR)/Frameworks
BIN_DIR = $(shell $(SWIFT) build -c $(CONFIGURATION) --show-bin-path)
VERIFY_BUNDLE := scripts/verify-app-bundle.sh
VERIFY_SIGNING_XATTRS := scripts/verify-bundle-signing-xattrs.sh

.PHONY: test app verify-app run clean print-release-credential-config create-local-certificate check-local-certificate sparkle-tools generate-eddsa-key check-eddsa-key validate-build-identity

test:
	swift test

print-release-credential-config:
	@printf '%s\n' \
		'LOCAL_CERTIFICATE_IDENTITY=$(LOCAL_CERTIFICATE_IDENTITY)' \
		'SPARKLE_KEYCHAIN_SERVICE=$(SPARKLE_KEYCHAIN_SERVICE)' \
		'SPARKLE_ACCOUNT=$(SPARKLE_ACCOUNT)'

create-local-certificate:
	@if $(SECURITY) find-identity -v -p codesigning | grep -Fq '"$(LOCAL_CERTIFICATE_IDENTITY)"'; then \
		echo "Reusing existing code signing identity: $(LOCAL_CERTIFICATE_IDENTITY)"; \
	elif $(SECURITY) find-certificate -c "$(LOCAL_CERTIFICATE_IDENTITY)" >/dev/null 2>&1; then \
		echo "Certificate exists without a usable private-key identity: $(LOCAL_CERTIFICATE_IDENTITY)" >&2; \
		exit 1; \
	else \
		tmpdir="$$(mktemp -d)"; \
		trap 'rm -rf "$$tmpdir"' EXIT; \
		printf '%s\n' \
			'[req]' \
			'distinguished_name = req_distinguished_name' \
			'x509_extensions = v3_req' \
			'prompt = no' \
			'[req_distinguished_name]' \
			'CN = $(LOCAL_CERTIFICATE_IDENTITY)' \
			'[v3_req]' \
			'basicConstraints = critical,CA:false' \
			'keyUsage = critical,digitalSignature' \
			'extendedKeyUsage = critical,codeSigning' \
			> "$$tmpdir/openssl.cnf"; \
		openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
			-keyout "$$tmpdir/$(LOCAL_CERTIFICATE_IDENTITY).key" \
			-out "$$tmpdir/$(LOCAL_CERTIFICATE_IDENTITY).crt" \
			-config "$$tmpdir/openssl.cnf" >/dev/null 2>&1; \
		p12_password="$$(openssl rand -base64 24)"; \
		legacy_args=(); \
		if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then legacy_args=(-legacy); fi; \
		openssl pkcs12 "$${legacy_args[@]}" -export \
			-passout pass:"$$p12_password" \
			-inkey "$$tmpdir/$(LOCAL_CERTIFICATE_IDENTITY).key" \
			-in "$$tmpdir/$(LOCAL_CERTIFICATE_IDENTITY).crt" \
			-out "$$tmpdir/$(LOCAL_CERTIFICATE_IDENTITY).p12" \
			-name "$(LOCAL_CERTIFICATE_IDENTITY)" >/dev/null 2>&1; \
		keychain="$$($(SECURITY) default-keychain | sed 's/^ *//; s/"//g')"; \
		$(SECURITY) import "$$tmpdir/$(LOCAL_CERTIFICATE_IDENTITY).p12" \
			-k "$$keychain" -P "$$p12_password" -T /usr/bin/codesign >/dev/null; \
		$(SECURITY) add-trusted-cert -d -r trustRoot -p codeSign \
			-k "$$keychain" "$$tmpdir/$(LOCAL_CERTIFICATE_IDENTITY).crt" >/dev/null; \
	fi
	@$(MAKE) check-local-certificate

check-local-certificate:
	@identity_fingerprint="$$($(SECURITY) find-identity -v -p codesigning | python3 -c 'import re,sys; identity=re.escape(sys.argv[1]); pattern=re.compile(r"\s*\d+\)\s+([0-9A-F]{40})\s+" + chr(34) + identity + chr(34)); matches=[match.group(1) for line in sys.stdin for match in [pattern.fullmatch(line.rstrip())] if match]; require=lambda condition,message: condition or (_ for _ in ()).throw(SystemExit(message)); require(len(matches) == 1,f"Expected exactly one usable {sys.argv[1]} identity; found {len(matches)}"); print(matches[0])' "$(LOCAL_CERTIFICATE_IDENTITY)")" || exit $$?; \
		certificate="$$($(SECURITY) find-certificate -c "$(LOCAL_CERTIFICATE_IDENTITY)" -a -p | python3 -c 'import base64,hashlib,re,sys; expected=sys.argv[1]; blocks=re.findall(r"-----BEGIN CERTIFICATE-----\s*.*?-----END CERTIFICATE-----",sys.stdin.read(),re.S); matches=[]; [(matches.append(block) if hashlib.sha1(base64.b64decode(re.sub(r"-----BEGIN CERTIFICATE-----|-----END CERTIFICATE-----|\s", "", block),validate=True)).hexdigest().upper() == expected else None) for block in blocks]; require=lambda condition,message: condition or (_ for _ in ()).throw(SystemExit(message)); require(len(matches) == 1,f"Expected exactly one same-CN certificate matching usable identity fingerprint; found {len(matches)}"); print(matches[0])' "$$identity_fingerprint")" || exit $$?; \
		printf '%s' "$$certificate" | python3 -c 'import datetime,re,subprocess,sys; certificate=sys.stdin.buffer.read(); identity=sys.argv[1]; require=lambda condition,message: condition or (_ for _ in ()).throw(SystemExit(message)); run=lambda *args: subprocess.run(["openssl","x509","-noout",*args],input=certificate,stdout=subprocess.PIPE,check=True).stdout.decode(); subject=run("-subject","-nameopt","RFC2253").strip(); require(subject == f"subject=CN={identity}",subject); text=run("-text"); require("Public-Key: (2048 bit)" in text,"Expected RSA-2048 public key"); require("Signature Algorithm: sha256WithRSAEncryption" in text,"Expected SHA-256 certificate signature"); extension_value=lambda name: (lambda match: match.group(1).strip() if match else (_ for _ in ()).throw(SystemExit(f"missing critical {name}")))(re.search(rf"X509v3 {re.escape(name)}: critical\s*\n\s*([^\n]+)",text)); require(extension_value("Basic Constraints") == "CA:FALSE","Expected critical Basic Constraints CA:FALSE"); require(extension_value("Key Usage") == "Digital Signature","Expected critical Key Usage Digital Signature"); require(extension_value("Extended Key Usage") == "Code Signing","Expected critical Extended Key Usage Code Signing"); dates=dict(line.split("=",1) for line in run("-startdate","-enddate").splitlines()); date_format="%b %d %H:%M:%S %Y %Z"; parse_date=lambda value: datetime.datetime.strptime(value,date_format).replace(tzinfo=datetime.timezone.utc); not_before=parse_date(dates["notBefore"]); not_after=parse_date(dates["notAfter"]); require(not_after-not_before == datetime.timedelta(days=3650),f"Expected 3650-day certificate validity; found {not_after-not_before}")' "$(LOCAL_CERTIFICATE_IDENTITY)"
	@tmpdir="$$(mktemp -d)"; \
		trap 'rm -rf "$$tmpdir"' EXIT; \
		probe="$$tmpdir/probe"; \
		printf '#!/bin/sh\nexit 0\n' > "$$probe"; \
		chmod +x "$$probe"; \
		$(CODESIGN) --force --sign "$(LOCAL_CERTIFICATE_IDENTITY)" "$$probe" >/dev/null; \
		$(CODESIGN) --verify --strict --verbose=2 "$$probe"; \
		echo "Code signing identity works: $(LOCAL_CERTIFICATE_IDENTITY)"

sparkle-tools:
	$(SWIFT) build -c debug
	test -x "$(SPARKLE_GENERATE_KEYS)"

generate-eddsa-key: sparkle-tools
	@created=0; \
		if $(SECURITY) find-generic-password \
			-s "$(SPARKLE_KEYCHAIN_SERVICE)" \
			-a "$(SPARKLE_ACCOUNT)" >/dev/null 2>&1; then \
			:; \
		else \
			"$(SPARKLE_GENERATE_KEYS)" --account "$(SPARKLE_ACCOUNT)" >/dev/null || exit $$?; \
			created=1; \
		fi; \
		public_key="$$($(SPARKLE_GENERATE_KEYS) --account "$(SPARKLE_ACCOUNT)" -p)" || exit $$?; \
		python3 -c 'import base64,sys; value=sys.argv[1]; valid=len(value) == 44 and value.endswith("=") and value.count("=") == 1 and len(base64.b64decode(value, validate=True)) == 32; sys.exit(0 if valid else 1)' "$$public_key" || { echo "Generated Sparkle public key is invalid" >&2; exit 1; }; \
		tmp_plist="$$(mktemp "$${TMPDIR:-/tmp}/drift-info-plist.XXXXXX")" || exit $$?; \
		trap 'rm -f "$$tmp_plist"' EXIT; \
		cp Info.plist "$$tmp_plist" || exit $$?; \
		if plutil -extract SUPublicEDKey raw "$$tmp_plist" >/dev/null 2>&1; then \
			plutil -replace SUPublicEDKey -string "$$public_key" "$$tmp_plist"; \
		else \
			plutil -insert SUPublicEDKey -string "$$public_key" "$$tmp_plist"; \
		fi || exit $$?; \
		plutil -lint "$$tmp_plist" >/dev/null || exit $$?; \
		mv "$$tmp_plist" Info.plist || exit $$?; \
		trap - EXIT; \
		if [[ "$$created" == 1 ]]; then \
			echo "Created Sparkle EdDSA key: $(SPARKLE_ACCOUNT)"; \
		else \
			echo "Reusing existing Sparkle EdDSA key: $(SPARKLE_ACCOUNT)"; \
		fi
	@$(MAKE) check-eddsa-key

check-eddsa-key: sparkle-tools
	@keychain_key="$$($(SPARKLE_GENERATE_KEYS) --account "$(SPARKLE_ACCOUNT)" -p)"; \
		plist_key="$$(plutil -extract SUPublicEDKey raw Info.plist)"; \
		test "$$keychain_key" = "$$plist_key" || { \
			echo "Sparkle Keychain public key does not match Info.plist SUPublicEDKey" >&2; \
			exit 1; \
		}; \
		python3 -c 'import base64,sys; value=sys.argv[1]; valid=len(value) == 44 and value.endswith("=") and value.count("=") == 1 and len(base64.b64decode(value, validate=True)) == 32; sys.exit(0 if valid else 1)' "$$plist_key" || { echo "Sparkle public key is invalid" >&2; exit 1; }; \
		! $(SECURITY) find-generic-password -s "$(SPARKLE_KEYCHAIN_SERVICE)" -a "$$plist_key" >/dev/null 2>&1
	@$(SECURITY) find-generic-password \
		-s "$(SPARKLE_KEYCHAIN_SERVICE)" \
		-a "$(SPARKLE_ACCOUNT)" >/dev/null

validate-build-identity:
	@$(IDENTITY_RESOLVER) "$(CONFIGURATION)" "$(APP_VARIANT)" variant >/dev/null
	@if [[ "$(RESOLVED_APP_VARIANT)" == "dev" ]] && \
		[[ -n "$(SPARKLE_FEED_URL)$(SPARKLE_PUBLIC_ED_KEY)" ]]; then \
		echo "Development builds do not accept Sparkle feed or public-key values" >&2; \
		exit 1; \
	fi
	@if [[ "$(RESOLVED_APP_VARIANT)" == "production" ]] && \
		[[ -n "$(SPARKLE_PUBLIC_ED_KEY)" ]] && [[ -z "$(SPARKLE_FEED_URL)" ]]; then \
		echo "SPARKLE_PUBLIC_ED_KEY override requires SPARKLE_FEED_URL" >&2; \
		exit 1; \
	fi

app: validate-build-identity
	$(SWIFT) build -c $(CONFIGURATION)
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS_DIR)" "$(FRAMEWORKS_DIR)"
	cp "$(BIN_DIR)/Drift" "$(MACOS_DIR)/Drift"
	cp Info.plist "$(CONTENTS_DIR)/Info.plist"
	plutil -replace CFBundleIdentifier -string "$(BUNDLE_IDENTIFIER)" "$(CONTENTS_DIR)/Info.plist"
	plutil -replace CFBundleName -string "$(PRODUCT_NAME)" "$(CONTENTS_DIR)/Info.plist"
	plutil -replace CFBundleDisplayName -string "$(PRODUCT_NAME)" "$(CONTENTS_DIR)/Info.plist"
	plutil -replace NSAccessibilityAccessDescription \
		-string "$(ACCESSIBILITY_DESCRIPTION)" "$(CONTENTS_DIR)/Info.plist"
	@framework="$$(find "$(BIN_DIR)" -type d -name Sparkle.framework -print -quit)"; \
	if [[ -z "$$framework" ]]; then \
		echo "Sparkle.framework was not produced by SwiftPM" >&2; \
		exit 1; \
	fi; \
	ditto --norsrc --noextattr "$$framework" "$(FRAMEWORKS_DIR)/Sparkle.framework"
	@if ! otool -l "$(MACOS_DIR)/Drift" | grep -A2 LC_RPATH | grep -Fq '@executable_path/../Frameworks'; then \
		install_name_tool -add_rpath '@executable_path/../Frameworks' "$(MACOS_DIR)/Drift"; \
	fi
	@if [[ "$(RESOLVED_APP_VARIANT)" == "dev" ]]; then \
		plutil -remove SUFeedURL "$(CONTENTS_DIR)/Info.plist" 2>/dev/null || true; \
		plutil -remove SUPublicEDKey "$(CONTENTS_DIR)/Info.plist" 2>/dev/null || true; \
	else \
		if [[ -n "$(SPARKLE_PUBLIC_ED_KEY)" ]]; then \
			plutil -replace SUPublicEDKey -string "$(SPARKLE_PUBLIC_ED_KEY)" "$(CONTENTS_DIR)/Info.plist"; \
		fi; \
		if [[ -n "$(SPARKLE_FEED_URL)" ]]; then \
			plutil -insert SUFeedURL -string "$(SPARKLE_FEED_URL)" "$(CONTENTS_DIR)/Info.plist" \
				2>/dev/null || plutil -replace SUFeedURL -string "$(SPARKLE_FEED_URL)" "$(CONTENTS_DIR)/Info.plist"; \
		else \
			plutil -remove SUFeedURL "$(CONTENTS_DIR)/Info.plist" 2>/dev/null || true; \
		fi; \
	fi
	@if [[ "$(RESOLVED_APP_VARIANT)" == "production" ]] && [[ -n "$(SPARKLE_FEED_URL)" ]]; then \
		[[ "$(SPARKLE_FEED_URL)" == https://* ]] || { echo "SUFeedURL must use HTTPS" >&2; exit 1; }; \
		key="$$(plutil -extract SUPublicEDKey raw "$(CONTENTS_DIR)/Info.plist")"; \
		if ! python3 -c 'import base64,sys; value=sys.argv[1]; sys.exit(0 if len(value) == 44 and value.endswith("=") and value.count("=") == 1 and len(base64.b64decode(value, validate=True)) == 32 else 1)' "$$key" 2>/dev/null; then \
			echo "Sparkle public key must be a 44-character padded Base64 value decoding to 32 bytes" >&2; \
			exit 1; \
		fi; \
	fi
	@function sign_if_present() { \
		if [[ -e "$$1" ]]; then codesign --force --sign "$(CODESIGN_IDENTITY)" "$$1"; fi; \
	}; \
	framework="$(FRAMEWORKS_DIR)/Sparkle.framework/Versions/B"; \
	sign_if_present "$$framework/XPCServices/Installer.xpc"; \
	sign_if_present "$$framework/XPCServices/Downloader.xpc"; \
	sign_if_present "$$framework/Autoupdate"; \
	sign_if_present "$$framework/Updater.app"; \
	codesign --force --sign "$(CODESIGN_IDENTITY)" "$(FRAMEWORKS_DIR)/Sparkle.framework"
	@find "$(APP_DIR)" -depth -exec xattr -d com.apple.FinderInfo {} + 2>/dev/null || true
	@find "$(APP_DIR)" -depth -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} + 2>/dev/null || true
	@$(SHELL) $(VERIFY_SIGNING_XATTRS) "$(APP_DIR)"
	@if [[ "$(CODESIGN_IDENTITY)" == "-" ]]; then \
		codesign --force --sign - \
			--requirements '=designated => identifier "$(BUNDLE_IDENTIFIER)"' \
			"$(APP_DIR)"; \
	else \
		codesign --force --sign "$(CODESIGN_IDENTITY)" "$(APP_DIR)"; \
	fi
	@$(SHELL) $(VERIFY_SIGNING_XATTRS) "$(APP_DIR)"
	codesign --verify --strict --verbose=2 "$(APP_DIR)"

verify-app: app
	@if [[ "$(RESOLVED_APP_VARIANT)" == "dev" ]]; then \
		mode=development; \
	elif [[ -n "$(SPARKLE_FEED_URL)" ]]; then \
		mode=production-configured; \
	else \
		mode=production-unconfigured; \
	fi; \
	$(VERIFY_BUNDLE) "$(APP_DIR)" "$$mode" "$(BUNDLE_IDENTIFIER)" "$(PRODUCT_NAME)"

run: verify-app
	open "$(APP_DIR)"

clean:
	rm -rf .build/app "$(BUILD_DIR)" .build
