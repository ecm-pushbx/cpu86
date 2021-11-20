
/*

Usage of the works is permitted provided that this
instrument is retained with the works, so that any entity
that uses the works is notified of this instrument.

DISCLAIMER: THE WORKS ARE WITHOUT WARRANTY.

*/

#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdlib.h>

#define BUFFERSIZE 8192

int main(int argc, char ** argv) {
	FILE* in;
	FILE* out;
	uint8_t buffer[BUFFERSIZE];
	uint16_t counter, bb;
	uint32_t length, filesize, processed = 0;
	uint32_t ii;
	if (argc < 4) {
		printf("Usage: %s in.bin out.mif length\n", argv[0]);
		return 1;
	}
	in = fopen(argv[1], "rb");
	if (NULL == in) {
		printf("Cannot open \"%s\" for reading\n", argv[1]);
		return 2;
	}
	out = fopen(argv[2], "w");
	if (NULL == out) {
		printf("Cannot open \"%s\" for writing\n", argv[2]);
		return 3;
	}
	length = atoi(argv[3]);
	if (0 == length) {
		printf("Invalid length in \"%s\"\n", argv[3]);
		return 4;
	}
	fseek(in, 0, SEEK_END);
	filesize = ftell(in);
	fseek(in, 0, SEEK_SET);
	if (filesize > length) {
		printf("Length \"%s\" is shorter than file \"%s\"\n", argv[3], argv[1]);
		return 5;
	}
	fprintf(out, "WIDTH=8;\nDEPTH=%"PRIu32";\n\n"
		"ADDRESS_RADIX=DEC;\nDATA_RADIX=BIN;\n\n"
		"CONTENT BEGIN\n\n", length);
	while ( (counter = fread(&buffer, 1, BUFFERSIZE, in)) != 0) {
		for (ii = 0; ii < counter; ++ii) {
			fprintf(out, "%"PRIu32" : ", processed);
			++ processed;
			for (bb = 0; bb < 8; ++bb) {
				fprintf(out, "%u", (buffer[ii] >> (7 - bb)) & 0x1);
			}
			fprintf(out, ";\n");
		}
	}
	if (processed != filesize) {
		printf("Unable to read from file \"%s\"\n", argv[1]);
		return 6;
	}
	for (ii = processed; ii < length; ++ii) {
		fprintf(out, "%"PRIu32" : 00000000;\n", processed);
		++ processed;
	}
	fprintf(out, "\nEND;\n");
	fclose(out);
	fclose(in);
	printf("Read %"PRIu32" bytes from input file\n", filesize);
}
