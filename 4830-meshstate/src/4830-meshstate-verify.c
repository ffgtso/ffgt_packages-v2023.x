/* SPDX-License-Identifier: MIT */

#include <ecdsautil/ecdsa.h>
#include <ecdsautil/sha256.h>
#include <libuecc/ecc.h>

#include <stdbool.h>
#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAX_SIGNATURES 32
#define MAX_PUBKEYS 64

static int hex_nibble(char c) {
	if (c >= '0' && c <= '9')
		return c - '0';
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if (c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return -1;
}

static bool parse_hex(void *out, size_t out_len, const char *hex) {
	unsigned char *p = out;

	if (!hex || strlen(hex) != out_len * 2)
		return false;

	for (size_t i = 0; i < out_len; i++) {
		int hi = hex_nibble(hex[2 * i]);
		int lo = hex_nibble(hex[2 * i + 1]);
		if (hi < 0 || lo < 0)
			return false;
		p[i] = (unsigned char)((hi << 4) | lo);
	}

	return true;
}

static bool parse_signature(ecdsa_signature_t *signature, const char *hex) {
	if (sizeof(*signature) != 64 || !hex || strlen(hex) != 128 ||
	    !parse_hex(signature, sizeof(*signature), hex))
		return false;

	/*
	 * libecdsautil < 0.4.1 failed to reject r == 0 or s == 0
	 * in the scalar field (CVE-2022-24884). Gluon 2021.1.2 ships
	 * the older ABI-compatible library, so apply the fixed library's
	 * checks here before calling ecdsa_verify_prepare_legacy().
	 */
	return !ecc_25519_gf_is_zero(&signature->r) &&
	       !ecc_25519_gf_is_zero(&signature->s);
}

static bool parse_pubkey(ecc_25519_work_t *pubkey, const char *hex) {
	ecc_int256_t packed;

	if (!parse_hex(packed.p, sizeof(packed.p), hex))
		return false;

	if (!ecc_25519_load_packed_legacy(pubkey, &packed))
		return false;

	return ecdsa_is_valid_pubkey(pubkey);
}

static bool hash_file(const char *path, ecc_int256_t *hash) {
	unsigned char buffer[4096];
	ecdsa_sha256_context_t ctx;
	FILE *f = fopen(path, "rb");
	if (!f)
		return false;

	ecdsa_sha256_init(&ctx);

	for (;;) {
		size_t n = fread(buffer, 1, sizeof(buffer), f);
		if (n > 0)
			ecdsa_sha256_update(&ctx, buffer, n);

		if (n < sizeof(buffer)) {
			if (ferror(f)) {
				fclose(f);
				return false;
			}
			break;
		}
	}

	fclose(f);
	ecdsa_sha256_final(&ctx, hash->p);
	return true;
}

static void usage(const char *name) {
	fprintf(stderr,
	        "Usage: %s -s SIGNATURE [-s SIGNATURE ...] "
	        "-p PUBKEY [-p PUBKEY ...] FILE\n",
	        name);
}

int main(int argc, char **argv) {
	ecdsa_signature_t signatures[MAX_SIGNATURES];
	ecc_25519_work_t pubkeys[MAX_PUBKEYS];
	size_t n_signatures = 0;
	size_t n_pubkeys = 0;
	int opt;

	while ((opt = getopt(argc, argv, "s:p:")) != -1) {
		switch (opt) {
		case 's':
			if (n_signatures >= MAX_SIGNATURES ||
			    !parse_signature(&signatures[n_signatures], optarg)) {
				fprintf(stderr, "Invalid signature\n");
				return 2;
			}
			n_signatures++;
			break;

		case 'p':
			if (n_pubkeys >= MAX_PUBKEYS ||
			    !parse_pubkey(&pubkeys[n_pubkeys], optarg)) {
				fprintf(stderr, "Invalid public key\n");
				return 2;
			}
			n_pubkeys++;
			break;

		default:
			usage(argv[0]);
			return 2;
		}
	}

	if (n_signatures == 0 || n_pubkeys == 0 || optind != argc - 1) {
		usage(argv[0]);
		return 2;
	}

	ecc_int256_t hash;
	if (!hash_file(argv[optind], &hash)) {
		fprintf(stderr, "Unable to hash payload\n");
		return 2;
	}

	/* 1-of-m verification: one valid signature/key pair is sufficient. */
	for (size_t i = 0; i < n_signatures; i++) {
		ecdsa_verify_context_t ctx;
		ecdsa_verify_prepare_legacy(&ctx, &hash, &signatures[i]);

		for (size_t j = 0; j < n_pubkeys; j++) {
			if (ecdsa_verify_legacy(&ctx, &pubkeys[j]))
				return 0;
		}
	}

	return 1;
}
