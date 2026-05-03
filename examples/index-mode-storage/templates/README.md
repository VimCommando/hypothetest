# Index Templates — index-mode-storage
#
# This directory contains Elasticsearch index template and pipeline definitions
# for the yelp-reviews benchmark index. Each variation has its own template
# file that declares the exact index settings for that variation.
#
# Files:
#   base-template.yml                          — standard mode, LZ4 codec, no sort
#                                                (used by the `standard` variation)
#   logsdb-template.yml                        — logsdb mode, LZ4 codec, sets
#                                                default_pipeline, maps @timestamp
#                                                (used by the `logsdb` variation)
#   standard-best-compression-template.yml     — standard mode, best_compression
#                                                (ZSTD) codec, no sort
#                                                (used by `standard_best_compression`)
#   standard-best-compression-sorted-template.yml — standard mode, best_compression
#                                                codec, index.sort.field: business_id
#                                                (used by `standard_best_compression_sorted`)
#   pipeline-date-to-timestamp.yml             — ingest pipeline: renames date → @timestamp
#                                                (used by the `logsdb` variation only)
#
# Templates and pipelines are NOT applied manually. espipe uploads them to
# Elasticsearch at load time via --template, --template-name, --pipeline, and
# --pipeline-name flags. No separate setup phase is needed (setup: []).
