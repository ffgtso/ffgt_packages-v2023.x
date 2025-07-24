// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2017 Matthias Schiffer <mschiffer@universe-factory.net>
// SPDX-FileCopyrightText: 2025 Kai 'wusel' Siering <wusel+src@uu.org>


#include <libplatforminfo.h>

#include <fcntl.h>
#include <getopt.h>
#include <math.h>
#include <signal.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include <sys/types.h>
#include <sys/file.h>
#include <sys/stat.h>


int main(int argc, char *argv[]) {
	if (!platforminfo_get_image_name()) {
		fputs("autoupdater: error: unsupported hardware model\n", stderr);
		return EXIT_FAILURE;
	}
	printf("%s\n", platforminfo_get_image_name());
	return;
}
