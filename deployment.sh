#!/bin/bash
set -euo pipefail


# Begin create_mycapstone_bucket.sh content

# Script to create and configure an S3 bucket for the capstone project.
# Default region: us-east-1

# variables
BUCKET="mycapstone-s3bucket"
REGION="${1:-us-east-1}"

# creating bucket
echo "Creating bucket: $BUCKET in region: $REGION"

# Check if the bucket exists or is accessible else create the bucket
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo "Bucket $BUCKET already exists or is accessible. Skipping create."
else

    if [[ "$REGION" == "us-east-1" ]]; then
        aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
    else
        aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION"
    fi
fi


# Disable per bucket public access block, this allows setting bucket policies that permit public reads.

echo "Disabling per-bucket public access block..."
aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

# Write a public-read bucket policy to a temp file
echo "Writing public-read bucket policy..."
cat > /tmp/${BUCKET}-policy.json <<'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowPublicRead",
            "Effect": "Allow",
            "Principal": "*",
            "Action": ["s3:GetObject"],
            "Resource": ["arn:aws:s3:::mycapstone-s3bucket/*"]
        }
    ]
}
EOF

# Apply the bucket policy to allow public reads
aws s3api put-bucket-policy --bucket "$BUCKET" --policy file:///tmp/${BUCKET}-policy.json


# Final status
echo "Bucket $BUCKET created/configured. Example upload:"
echo "  aws s3 cp ./localfile.txt s3://$BUCKET/localfile.txt --acl public-read"

# -----------------------------
# End create_mycapstone_bucket.sh content
# -----------------------------


# -----------------------------
# Begin filemanager.sh content
# -----------------------------

set -euo pipefail

# variables
# BUCKET is already defined above
NAME="Seun"

# logging setup
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/storage-$(date -u +%Y%m%dT%H%M%SZ).log"

log() {
    # simple structured log: timestamp, level, message
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    echo "[$ts] [$level] $msg" | tee -a "$LOG_FILE"
}

run() {
    # run a command, capture stdout/stderr, exitcode, and log details
    local cmd=("$@")
    log INFO "RUN: ${cmd[*]}"
    local out
    if out="$("${cmd[@]}" 2>&1)"; then
        log INFO "OK: ${cmd[*]}"
        # write first 2000 chars of output to log to avoid huge logs
        printf '%s\n' "$out" | head -n 2000 >> "$LOG_FILE"
        return 0
    else
        local rc=$?
        log ERROR "FAILED(rc=$rc): ${cmd[*]}"
        printf '%s\n' "$out" | head -n 2000 >> "$LOG_FILE"
        return $rc
    fi
}

# record caller identity
if run aws sts get-caller-identity --output json; then
    log INFO "Recorded AWS caller identity"
else
    log WARN "Unable to record AWS caller identity - check AWS CLI config/credentials"
fi

# create file to be uploaded into the bucket
log INFO "Creating test file for upload"
echo "My name is $NAME" > file1.txt

# upload file to the bucket
log INFO "Uploading file file1.txt to bucket $BUCKET"
if run aws s3 cp file1.txt s3://"$BUCKET"/; then
    log INFO "Upload successful: file1.txt -> s3://$BUCKET/file1.txt"
else
    log ERROR "Upload failed: file1.txt -> s3://$BUCKET/"
fi

# listing files in the bucket
log INFO "Listing available files in $BUCKET"
if run aws s3 ls s3://"$BUCKET"/ --recursive; then
    log INFO "Listed files in $BUCKET"
else
    log ERROR "Failed to list files in $BUCKET"
fi

# deleting test file in the bucket
log INFO "Deleting test file s3://$BUCKET/file1.txt"
if run aws s3 rm s3://"$BUCKET"/file1.txt; then
    log INFO "Deleted s3://$BUCKET/file1.txt"
else
    log ERROR "Failed to delete s3://$BUCKET/file1.txt"
fi

log INFO "script completed"

# -----------------------------
# End filemanager.sh content
# -----------------------------

echo "Combined deployment finished. See $LOG_FILE for filemanager logs."
