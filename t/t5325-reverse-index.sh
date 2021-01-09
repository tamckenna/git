#!/bin/sh

test_description='on-disk reverse index'
. ./test-lib.sh

# The below tests want control over the 'pack.writeReverseIndex' setting
# themselves to assert various combinations of it with other options.
sane_unset GIT_TEST_WRITE_REV_INDEX

packdir=.git/objects/pack

test_expect_success 'setup' '
	test_commit base &&

	pack=$(git pack-objects --all $packdir/pack) &&
	rev=$packdir/pack-$pack.rev &&

	test_path_is_missing $rev
'

test_index_pack () {
	rm -f $rev &&
	conf=$1 &&
	shift &&
	# remove the index since Windows won't overwrite an existing file
	rm $packdir/pack-$pack.idx &&
	git -c pack.writeReverseIndex=$conf index-pack "$@" \
		$packdir/pack-$pack.pack
}

test_expect_success 'index-pack with pack.writeReverseIndex' '
	test_index_pack "" &&
	test_path_is_missing $rev &&

	test_index_pack false &&
	test_path_is_missing $rev &&

	test_index_pack true &&
	test_path_is_file $rev
'

test_expect_success 'index-pack with --[no-]rev-index' '
	for conf in "" true false
	do
		test_index_pack "$conf" --rev-index &&
		test_path_exists $rev &&

		test_index_pack "$conf" --no-rev-index &&
		test_path_is_missing $rev
	done
'

test_expect_success 'index-pack can verify reverse indexes' '
	test_when_finished "rm -f $rev" &&
	test_index_pack true &&

	test_path_is_file $rev &&
	git index-pack --rev-index --verify $packdir/pack-$pack.pack &&

	# Intentionally corrupt the reverse index.
	chmod u+w $rev &&
	printf "xxxx" | dd of=$rev bs=1 count=4 conv=notrunc &&

	test_must_fail git index-pack --rev-index --verify \
		$packdir/pack-$pack.pack 2>err &&
	grep "validation error" err
'

test_expect_success 'index-pack infers reverse index name with -o' '
	git index-pack --rev-index -o other.idx $packdir/pack-$pack.pack &&
	test_path_is_file other.idx &&
	test_path_is_file other.rev
'

test_expect_success 'pack-objects respects pack.writeReverseIndex' '
	test_when_finished "rm -fr pack-1-*" &&

	git -c pack.writeReverseIndex= pack-objects --all pack-1 &&
	test_path_is_missing pack-1-*.rev &&

	git -c pack.writeReverseIndex=false pack-objects --all pack-1 &&
	test_path_is_missing pack-1-*.rev &&

	git -c pack.writeReverseIndex=true pack-objects --all pack-1 &&
	test_path_is_file pack-1-*.rev
'

test_expect_success 'reverse index is not generated when available on disk' '
	test_index_pack true &&
	test_path_is_file $rev &&

	git rev-parse HEAD >tip &&
	GIT_TEST_REV_INDEX_DIE_IN_MEMORY=1 git cat-file \
		--batch-check="%(objectsize:disk)" <tip
'

revindex_tests () {
	on_disk="$1"

	test_expect_success "setup revindex tests (on_disk=$on_disk)" "
		test_oid_cache <<-EOF &&
		disklen sha1:47
		disklen sha256:59
		EOF

		git init repo &&
		(
			cd repo &&

			if test ztrue = \"z$on_disk\"
			then
				git config pack.writeReverseIndex true
			fi &&

			test_commit commit &&
			git repack -ad
		)

	"

	test_expect_success "check objectsize:disk (on_disk=$on_disk)" '
		(
			cd repo &&
			git rev-parse HEAD^{tree} >tree &&
			git cat-file --batch-check="%(objectsize:disk)" <tree >actual &&

			git cat-file -p HEAD^{tree} &&

			printf "%s\n" "$(test_oid disklen)" >expect &&
			test_cmp expect actual
		)
	'

	test_expect_success "cleanup revindex tests (on_disk=$on_disk)" '
		rm -fr repo
	'
}

revindex_tests "true"
revindex_tests "false"

test_done
