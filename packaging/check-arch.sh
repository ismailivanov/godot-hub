#!/bin/sh
# Fails unless <file> is an ELF (Linux binary or AppImage) or PE (Windows) executable
# built for <arch>, so a release never ships a binary under the wrong asset name.
set -eu

if [ "$#" -ne 2 ]; then
	echo "Usage: $0 <file> <x86_64|arm64>" >&2
	exit 2
fi

file=$1
case "$2" in
	x86_64) elf_machine=62 pe_machine=34404 ;; # EM_X86_64, IMAGE_FILE_MACHINE_AMD64
	arm64 | aarch64) elf_machine=183 pe_machine=43620 ;; # EM_AARCH64, IMAGE_FILE_MACHINE_ARM64
	*)
		echo "Unsupported architecture: $2 (expected x86_64 or arm64)" >&2
		exit 2
		;;
esac

if [ ! -s "$file" ]; then
	echo "Missing or empty file: $file" >&2
	exit 1
fi

# Prints the little-endian unsigned integer of <size> bytes at <offset> in $file.
read_le() {
	od -An -tu1 -v -j "$1" -N "$2" "$file" | awk '
		{ for (i = 1; i <= NF; i++) bytes[count++] = $i }
		END {
			value = 0
			for (i = count - 1; i >= 0; i--) value = value * 256 + bytes[i]
			printf "%.0f\n", value
		}'
}

magic=$(od -An -c -N 4 "$file" | tr -d ' ')
case "$magic" in
	'177ELF')
		# e_ident[EI_DATA] must say little-endian before e_machine can be read as such.
		if [ "$(read_le 5 1)" -ne 1 ]; then
			echo "$file: not a little-endian ELF file" >&2
			exit 1
		fi
		kind=ELF
		expected=$elf_machine
		machine=$(read_le 18 2)
		;;
	MZ*)
		pe_offset=$(read_le 60 4)
		if [ "$(od -An -c -j "$pe_offset" -N 4 "$file" | tr -d ' ')" != 'PE\0\0' ]; then
			echo "$file: no PE header at offset $pe_offset" >&2
			exit 1
		fi
		kind=PE
		expected=$pe_machine
		machine=$(read_le $((pe_offset + 4)) 2)
		;;
	*)
		echo "$file: neither an ELF nor a PE file" >&2
		exit 1
		;;
esac

if [ "$machine" -ne "$expected" ]; then
	echo "$file: $kind machine $machine, expected $expected for $2" >&2
	exit 1
fi
echo "$file: $kind $2"
