# Security Best Practices for staRburst

## Security Best Practices for staRburst

This guide covers security considerations for deploying and using
staRburst in production environments.

### 1. Credential Management

#### ❌ DON’T: Hard-code Credentials

**Never** hard-code AWS credentials in your code:

``` r
# NEVER DO THIS - credentials exposed in code
Sys.setenv(
  AWS_ACCESS_KEY_ID = "AKIA...",
  AWS_SECRET_ACCESS_KEY = "wJalr..."
)
```

**Why it’s dangerous:** - Credentials in code can be committed to
version control - Logs may capture environment variables - Code sharing
exposes credentials

#### ✅ DO: Use IAM Roles (Recommended)

When running on AWS infrastructure (EC2, ECS, Lambda):

``` r
# No credentials needed - automatically uses instance/task IAM role
library(starburst)
plan(starburst, workers = 10)
```

**Benefits:** - No credential management required - Automatic credential
rotation - Fine-grained permissions via IAM policies - Audit trail via
CloudTrail

**Setup:** 1. Create IAM role with required permissions 2. Attach role
to EC2 instance or ECS task 3. staRburst automatically discovers and
uses role credentials

#### ✅ DO: Use Named Profiles (Local Development)

For local development, use AWS CLI profiles:

``` r
# Credentials stored in ~/.aws/credentials
Sys.setenv(AWS_PROFILE = "my-starburst-profile")

library(starburst)
plan(starburst, workers = 10)
```

**Setup:**

``` bash
# Configure AWS CLI profile
aws configure --profile my-starburst-profile
```

#### ✅ DO: Use Temporary Credentials (STS)

For cross-account access or enhanced security:

``` r
library(paws.security.identity)
sts <- paws.security.identity::sts()

# Assume role with MFA
credentials <- sts$assume_role(
  RoleArn = "arn:aws:iam::123456789012:role/StarburstRole",
  RoleSessionName = "starburst-session",
  SerialNumber = "arn:aws:iam::123456789012:mfa/user",
  TokenCode = "123456"  # MFA token
)

# Use temporary credentials
Sys.setenv(
  AWS_ACCESS_KEY_ID = credentials$Credentials$AccessKeyId,
  AWS_SECRET_ACCESS_KEY = credentials$Credentials$SecretAccessKey,
  AWS_SESSION_TOKEN = credentials$Credentials$SessionToken
)
```

**Benefits:** - Time-limited credentials (expire after 1-12 hours) - Can
require MFA for sensitive operations - Separate credentials for
different roles

### 2. S3 Bucket Security

#### Minimum Required Permissions

Create an IAM policy for staRburst workers:

``` json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "StarburstWorkerAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-starburst-bucket",
        "arn:aws:s3:::my-starburst-bucket/*"
      ],
      "Condition": {
        "StringLike": {
          "s3:prefix": ["sessions/*", "tasks/*", "results/*"]
        }
      }
    }
  ]
}
```

#### Enable Server-Side Encryption

Encrypt data at rest in S3:

``` r
# Option 1: Enable default encryption via AWS Console or CLI
library(paws.storage)
s3 <- paws.storage::s3()

s3$put_bucket_encryption(
  Bucket = "my-starburst-bucket",
  ServerSideEncryptionConfiguration = list(
    Rules = list(
      list(
        ApplyServerSideEncryptionByDefault = list(
          SSEAlgorithm = "AES256"  # Or "aws:kms" for KMS
        ),
        BucketKeyEnabled = TRUE
      )
    )
  )
)
```

**Encryption Options:** - **AES256** - S3-managed keys (SSE-S3, free) -
**aws:kms** - AWS KMS managed keys (SSE-KMS, more control, costs
apply) - **aws:kms:dsse** - Dual-layer encryption for compliance
(SSE-KMS-DSSE)

#### Enable Versioning

Protect against accidental deletion:

``` r
s3$put_bucket_versioning(
  Bucket = "my-starburst-bucket",
  VersioningConfiguration = list(
    Status = "Enabled"
  )
)
```

**Benefits:** - Recover from accidental deletions - Rollback to previous
versions - Required for certain compliance frameworks

#### Block Public Access

Ensure bucket is never publicly accessible:

``` r
s3$put_public_access_block(
  Bucket = "my-starburst-bucket",
  PublicAccessBlockConfiguration = list(
    BlockPublicAcls = TRUE,
    IgnorePublicAcls = TRUE,
    BlockPublicPolicy = TRUE,
    RestrictPublicBuckets = TRUE
  )
)
```

#### Use Bucket Policies

Restrict access to specific IAM roles:

``` json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnencryptedObjectUploads",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::my-starburst-bucket/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption": "AES256"
        }
      }
    },
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::my-starburst-bucket/*",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

### 3. Network Isolation

#### Use Private Subnets (For Sensitive Workloads)

Deploy workers in private subnets without internet access:

``` r
library(starburst)

# Configure to use private subnets
starburst_config(
  subnets = c("subnet-private-1a", "subnet-private-1b"),
  security_groups = c("sg-starburst-workers")
)

plan(starburst, workers = 10)
```

**Requirements for Private Subnets:** - VPC endpoints for S3, ECR,
CloudWatch Logs - NAT Gateway if internet access needed for some
operations

#### Configure Security Groups

Minimal security group (no inbound, only outbound):

``` json
{
  "GroupName": "starburst-workers",
  "Description": "Security group for staRburst ECS tasks",
  "VpcId": "vpc-...",
  "SecurityGroupIngress": [],
  "SecurityGroupEgress": [
    {
      "IpProtocol": "tcp",
      "FromPort": 443,
      "ToPort": 443,
      "CidrIp": "0.0.0.0/0",
      "Description": "HTTPS to AWS services"
    }
  ]
}
```

#### Enable VPC Endpoints (Recommended)

Avoid internet traffic for AWS service calls:

**S3 Gateway Endpoint** (free):

``` bash
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-... \
  --service-name com.amazonaws.us-east-1.s3 \
  --route-table-ids rtb-...
```

**ECR Interface Endpoints** (charges apply):

``` bash
# ECR API endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-... \
  --service-name com.amazonaws.us-east-1.ecr.api \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-... \
  --security-group-ids sg-...

# ECR Docker endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-... \
  --service-name com.amazonaws.us-east-1.ecr.dkr \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-... \
  --security-group-ids sg-...
```

**CloudWatch Logs Endpoint**:

``` bash
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-... \
  --service-name com.amazonaws.us-east-1.logs \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-... \
  --security-group-ids sg-...
```

**Benefits:** - All AWS API traffic stays within AWS network - Reduced
data transfer costs - Better security posture (no internet exposure)

### 4. Cost Controls

#### Set Budget Alerts

Create AWS Budget to monitor staRburst costs:

1.  Go to **AWS Billing Console → Budgets**
2.  Click **Create budget**
3.  Choose **Cost budget**
4.  Set monthly budget (e.g., \$500)
5.  Configure alerts:
    - 50% actual spend → Email warning
    - 80% actual spend → Email alert
    - 100% actual spend → Email urgent alert + SNS notification

#### Use Worker Limits

staRburst enforces maximum 500 workers per plan:

``` r
# This will error - prevents accidental huge deployments
plan(starburst, workers = 10000)
# Error: Workers must be <= 500

# Maximum allowed
plan(starburst, workers = 500)
```

#### Monitor Active Sessions

Regularly check for orphaned sessions:

``` r
# List all sessions
sessions <- starburst_list_sessions()
print(sessions)

# Cleanup old sessions
for (session_id in sessions$session_id) {
  # Check if session is old
  created_date <- as.Date(sessions$created_at[sessions$session_id == session_id])
  if (Sys.Date() - created_date > 7) {
    cat(sprintf("Cleaning up old session: %s\n", session_id))
    session <- starburst_session_attach(session_id)
    session$cleanup(stop_workers = TRUE, force = TRUE)
  }
}
```

#### Use Absolute Timeouts

Prevent sessions from running indefinitely:

``` r
# Session auto-terminates after 24 hours
session <- starburst_session(
  workers = 10,
  absolute_timeout = 86400  # 24 hours in seconds
)
```

#### Cost Estimation

Before launching large jobs:

``` r
# Estimate cost
workers <- 100
cpu <- 4
memory_gb <- 8
runtime_hours <- 2

# Fargate pricing (us-east-1, 2026)
vcpu_price <- 0.04048
memory_price <- 0.004445

cost_per_worker <- (cpu * vcpu_price) + (memory_gb * memory_price)
total_cost <- workers * cost_per_worker * runtime_hours

cat(sprintf("Estimated cost: $%.2f for %d hours\n", total_cost, runtime_hours))
# Estimated cost: $19.84 for 2 hours
```

### 5. Audit Logging

#### Enable CloudTrail

Capture all API calls for security auditing:

1.  **AWS Console → CloudTrail**
2.  **Create trail**
3.  **Apply to all regions**
4.  **Enable for management events**
5.  **Enable for data events** (optional, for S3 object-level logging)

**What CloudTrail Captures:** - Who launched staRburst workers (IAM
user/role) - When tasks were created/stopped - S3 object access (if data
events enabled) - API failures and authorization errors

#### Enable CloudWatch Logs

staRburst automatically logs to CloudWatch:

- **Log Group:** `/aws/ecs/starburst-worker`
- **Retention:** 7 days (default)

Increase retention for compliance:

``` r
library(paws.management)
logs <- paws.management::cloudwatchlogs()

logs$put_retention_policy(
  logGroupName = "/aws/ecs/starburst-worker",
  retentionInDays = 30  # or 90, 180, 365, etc.
)
```

#### Enable S3 Access Logging

Track all S3 bucket access:

``` r
s3$put_bucket_logging(
  Bucket = "my-starburst-bucket",
  BucketLoggingStatus = list(
    LoggingEnabled = list(
      TargetBucket = "my-logging-bucket",
      TargetPrefix = "starburst-access-logs/"
    )
  )
)
```

**Access logs include:** - Who accessed objects - When objects were
accessed - What operations were performed - Source IP addresses

#### Review Security Events

Regularly review logs for suspicious activity:

``` r
# CloudWatch Insights query for failed authentications
library(paws.management)
logs <- paws.management::cloudwatchlogs()

# Query for errors in last 24 hours
query <- "fields @timestamp, @message
| filter @message like /ERROR|AccessDenied|Forbidden/
| sort @timestamp desc"

start_time <- as.integer(Sys.time() - 86400)  # 24 hours ago
end_time <- as.integer(Sys.time())

result <- logs$start_query(
  logGroupName = "/aws/ecs/starburst-worker",
  startTime = start_time,
  endTime = end_time,
  queryString = query
)
```

### 6. Data Protection

#### Minimize Data Uploaded to S3

Only send necessary data to workers:

``` r
# ✅ Good - only send needed data
large_data <- read.csv("huge_dataset.csv")
sample_data <- large_data[1:1000, ]  # Use sample for testing

plan(starburst, workers = 10)
results <- future_map(1:10, function(i) {
  # sample_data automatically uploaded as global
  analyze(sample_data[i, ])
})

# ❌ Bad - sends entire large dataset
plan(starburst, workers = 10)
results <- future_map(1:10, function(i) {
  analyze(large_data[i, ])  # Uploads all of large_data
})
```

#### Delete Results After Collection

``` r
# Collect and immediately delete from S3
session <- starburst_session(workers = 10)
task_id <- session$submit(quote(sensitive_computation()))

# Wait for completion
results <- session$collect(wait = TRUE)

# Immediately cleanup (force = TRUE deletes S3 files)
session$cleanup(force = TRUE)

# Save results locally if needed
saveRDS(results, "local_results.rds")
```

#### Consider Client-Side Encryption

For highly sensitive data:

``` r
# Encrypt before upload
library(sodium)

# Generate key (store securely, e.g., AWS Secrets Manager)
key <- random(32)

# Encrypt data before passing to future
sensitive_data <- serialize(my_data, NULL)
encrypted_data <- data_encrypt(sensitive_data, key)

# Run computation
plan(starburst, workers = 1)
result <- future({
  # Decrypt in worker
  decrypted <- data_decrypt(encrypted_data, key)
  my_data <- unserialize(decrypted)
  # Process...
})
```

### 7. Container Image Security

#### Use Minimal Base Images

staRburst uses multi-stage builds to minimize image size:

- Base image includes only essential R packages
- Project images layer on top of base
- Smaller images = fewer potential vulnerabilities

#### Scan Images for Vulnerabilities

Enable ECR image scanning:

``` r
library(paws.compute)
ecr <- paws.compute::ecr()

ecr$put_image_scanning_configuration(
  repositoryName = "starburst-worker",
  imageScanningConfiguration = list(
    scanOnPush = TRUE
  )
)
```

#### Use Image Lifecycle Policies

Automatically delete old images:

``` r
# Delete images older than 30 days
ecr$put_lifecycle_policy(
  repositoryName = "starburst-worker",
  lifecyclePolicyText = jsonlite::toJSON(list(
    rules = list(
      list(
        rulePriority = 1,
        description = "Delete old images",
        selection = list(
          tagStatus = "any",
          countType = "sinceImagePushed",
          countUnit = "days",
          countNumber = 30
        ),
        action = list(type = "expire")
      )
    )
  ), auto_unbox = TRUE)
)
```

### 8. Compliance Considerations

#### HIPAA Compliance

For HIPAA-regulated workloads:

1.  **Sign AWS Business Associate Agreement (BAA)**
2.  **Use only HIPAA-eligible services** (Fargate, S3, ECR are eligible)
3.  **Enable encryption** at rest (S3, EBS) and in transit (TLS)
4.  **Enable audit logging** (CloudTrail, CloudWatch Logs)
5.  **Implement access controls** (IAM, VPC, Security Groups)
6.  **Use private subnets** with VPC endpoints

#### GDPR Compliance

For EU data processing:

1.  **Use EU regions** (eu-west-1, eu-central-1, etc.)
2.  **Enable encryption** for data at rest and in transit
3.  **Implement data retention policies** (auto-delete after N days)
4.  **Enable audit logging** for data access
5.  **Document data processing** activities
6.  **Implement right to erasure** (cleanup mechanisms)

#### SOC 2 Compliance

For SOC 2 compliance:

1.  **Enable CloudTrail** in all regions
2.  **Enable AWS Config** for configuration compliance
3.  **Use AWS Organizations** for multi-account management
4.  **Implement least-privilege IAM** policies
5.  **Enable MFA** for all IAM users
6.  **Review access quarterly**

### 9. Incident Response

#### If Credentials Are Compromised

**Immediate Actions:** 1. **Disable/rotate credentials** immediately 2.
**Review CloudTrail logs** for unauthorized activity 3. **Check for new
resources** created by attacker 4. **Terminate suspicious ECS tasks** 5.
**Review S3 bucket access logs**

``` r
# List all active sessions
sessions <- starburst_list_sessions()

# Check for sessions you didn't create
print(sessions)

# Cleanup suspicious sessions
for (session_id in suspicious_ids) {
  session <- starburst_session_attach(session_id)
  session$cleanup(stop_workers = TRUE, force = TRUE)
}
```

#### If Data Breach Suspected

1.  **Isolate affected resources** (change security groups)
2.  **Review S3 access logs** for unauthorized downloads
3.  **Check CloudTrail** for API calls
4.  **Preserve evidence** (don’t delete logs)
5.  **Notify security team** and legal counsel
6.  **Follow incident response plan**

### 10. Security Checklist

Before deploying staRburst to production:

Use IAM roles instead of long-term credentials

Enable S3 bucket encryption (SSE-S3 or SSE-KMS)

Enable S3 versioning

Block public access to S3 bucket

Use private subnets for sensitive workloads

Configure VPC endpoints for AWS services

Create security group with minimal permissions

Enable CloudTrail in all regions

Enable CloudWatch Logs with appropriate retention

Set up AWS Budget alerts

Limit maximum workers to prevent runaway costs

Enable ECR image scanning

Implement image lifecycle policies

Document data classification and handling

Train team on security best practices

Establish incident response procedures

Review IAM policies quarterly

Test backup and recovery procedures

### Additional Resources

- [AWS Security Best
  Practices](https://aws.amazon.com/architecture/security-identity-compliance/)
- [AWS Well-Architected Security
  Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)
- [CIS AWS Foundations
  Benchmark](https://www.cisecurity.org/benchmark/amazon_web_services)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)

### See Also

- [Troubleshooting
  Guide](https://starburst.ing/articles/troubleshooting.md) - Diagnose
  and fix common issues
- [staRburst README](https://github.com/scttfrdmn/starburst) - Getting
  started guide
