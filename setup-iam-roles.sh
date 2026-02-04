#!/bin/bash
# Setup IAM roles for staRburst
# Run with: AWS_PROFILE=aws ./setup-iam-roles.sh

set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_REGION:-us-east-1}

echo "Setting up IAM roles for staRburst"
echo "Account ID: $ACCOUNT_ID"
echo "Region: $REGION"
echo ""

# 1. Create ECS Execution Role
echo "1. Creating ECS Execution Role..."

cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ecs-tasks.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

if aws iam get-role --role-name starburstECSExecutionRole 2>/dev/null; then
  echo "   • starburstECSExecutionRole already exists"
else
  aws iam create-role \
    --role-name starburstECSExecutionRole \
    --assume-role-policy-document file:///tmp/trust-policy.json \
    --description "Execution role for staRburst ECS tasks"

  echo "   ✓ Created starburstECSExecutionRole"
fi

# Attach managed policies
aws iam attach-role-policy \
  --role-name starburstECSExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
  2>/dev/null || echo "   • Policy already attached"

aws iam attach-role-policy \
  --role-name starburstECSExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly \
  2>/dev/null || echo "   • Policy already attached"

echo ""

# 2. Create ECS Task Role
echo "2. Creating ECS Task Role..."

if aws iam get-role --role-name starburstECSTaskRole 2>/dev/null; then
  echo "   • starburstECSTaskRole already exists"
else
  aws iam create-role \
    --role-name starburstECSTaskRole \
    --assume-role-policy-document file:///tmp/trust-policy.json \
    --description "Task role for staRburst workers"

  echo "   ✓ Created starburstECSTaskRole"
fi

# Create S3 access policy
cat > /tmp/s3-policy.json <<EOF
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
EOF

aws iam put-role-policy \
  --role-name starburstECSTaskRole \
  --policy-name StarburstS3Access \
  --policy-document file:///tmp/s3-policy.json

echo "   ✓ Attached S3 access policy"

# Cleanup
rm /tmp/trust-policy.json /tmp/s3-policy.json

echo ""
echo "✓ IAM roles setup complete!"
echo ""
echo "Role ARNs:"
echo "  Execution: arn:aws:iam::${ACCOUNT_ID}:role/starburstECSExecutionRole"
echo "  Task:      arn:aws:iam::${ACCOUNT_ID}:role/starburstECSTaskRole"
echo ""
echo "Next step: Run test with starburst_map()"
