# IAM Roles Setup for staRburst

staRburst requires two IAM roles to run tasks on AWS Fargate:

1. **ECS Execution Role** - Used by ECS to pull Docker images and write logs
2. **ECS Task Role** - Used by worker containers to access S3

## Quick Setup (Automated)

Run the provided script:

```bash
AWS_PROFILE=aws ./setup-iam-roles.sh
```

This creates both roles with the correct policies.

## Manual Setup

### 1. ECS Execution Role: `starburstECSExecutionRole`

**Purpose:** Allows ECS to pull Docker images from ECR and write logs to CloudWatch.

#### Trust Policy
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ecs-tasks.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
```

#### Attach Managed Policies
- `arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy`
- `arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly`

#### AWS CLI Commands
```bash
# Create role
aws iam create-role \
  --role-name starburstECSExecutionRole \
  --assume-role-policy-document file://trust-policy.json \
  --description "Execution role for staRburst ECS tasks"

# Attach policies
aws iam attach-role-policy \
  --role-name starburstECSExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

aws iam attach-role-policy \
  --role-name starburstECSExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

### 2. ECS Task Role: `starburstECSTaskRole`

**Purpose:** Allows worker containers to read/write task data from S3.

#### Trust Policy
Same as Execution Role (above)

#### Inline Policy: `StarburstS3Access`
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ],
    "Resource": [
      "arn:aws:s3:::starburst-*",
      "arn:aws:s3:::starburst-*/*"
    ]
  }]
}
```

#### AWS CLI Commands
```bash
# Create role
aws iam create-role \
  --role-name starburstECSTaskRole \
  --assume-role-policy-document file://trust-policy.json \
  --description "Task role for staRburst workers"

# Attach inline policy
aws iam put-role-policy \
  --role-name starburstECSTaskRole \
  --policy-name StarburstS3Access \
  --policy-document file://s3-policy.json
```

## Verification

After creating the roles, verify they exist:

```bash
# Check execution role
aws iam get-role --role-name starburstECSExecutionRole

# Check task role
aws iam get-role --role-name starburstECSTaskRole

# List attached policies
aws iam list-attached-role-policies --role-name starburstECSExecutionRole
aws iam list-role-policies --role-name starburstECSTaskRole
```

## Role ARNs

After creation, your role ARNs will be:
```
arn:aws:iam::<YOUR_ACCOUNT_ID>:role/starburstECSExecutionRole
arn:aws:iam::<YOUR_ACCOUNT_ID>:role/starburstECSTaskRole
```

staRburst automatically constructs these ARNs using your AWS account ID from the configuration.

## Troubleshooting

### "Access Denied" when creating roles
- Ensure your AWS user/role has `iam:CreateRole` and `iam:AttachRolePolicy` permissions
- You may need the `IAMFullAccess` managed policy

### "Role already exists" error
- The roles are already created - you're good to go!
- Or delete existing roles first: `aws iam delete-role --role-name <ROLE_NAME>`

### Tasks fail with "AccessDenied" for S3
- Check that the task role has the S3 policy attached
- Verify the S3 bucket name matches the pattern `starburst-*`

### Tasks fail to start
- Check CloudWatch Logs for error messages
- Verify the execution role can access ECR: `aws ecr describe-repositories`
