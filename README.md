# terraform-aws-environments

Small Terraform setup for AWS (one S3 bucket + one EC2 instance) with three environments and
GitHub Actions for plan on PR and deploy dev -> staging -> prod.

## Layout

```
modules/app-stack/        the module: bucket, ec2, iam
envs/dev|staging|prod/    one folder per env, own backend + tfvars, calls the module
bootstrap/                run once per env: state bucket, github oidc, plan/apply roles
.github/workflows/        terraform-plan.yml, terraform-apply.yml
.github/CODEOWNERS        who has to review changes to envs, modules and workflows
```

I used a folder per environment instead of workspaces. Each env has its own state file, its own
tfvars and its own AWS role, so a mistake in dev can't touch prod and the differences between
envs are visible in the diff. All logic lives in the module.

## How environments are separated

- **State:** one S3 bucket per env (`barba-tfstate-<env>`), versioned and encrypted, with S3 native locking.
- **Names:** everything is prefixed `<project>-<env>`, so nothing collides.
- **Config:** each env has its own `terraform.tfvars` (instance size, force_destroy, termination protection).
- **Credentials:** GitHub OIDC, no access keys anywhere. Each env has a read-only plan role and an apply role.
  The apply role can only be assumed by a job running in the matching GitHub environment.

All three envs live in one AWS account here to keep the test simple. In a real setup each env
would be its own account, the only thing that changes is which account bootstrap is run against.

## Branches and promotion

One branch per environment:

    feature/* -> dev -> staging -> main (prod)

- PR into `dev`: fmt, validate and a plan against dev, posted as a PR comment. Merge applies dev.
- PR `dev` -> `staging`: plan against staging. Merge applies staging.
- PR `staging` -> `main`: plan against prod. Merge runs a plan and then waits for a manual approval before apply.

A check called "Enforce promotion path" fails any PR that skips a step (for example feature -> main),
so the only way to prod is through dev and staging. Promotion PRs use merge commits, not squash,
otherwise the branches drift apart. The branch decides the environment, the folders exist in every
branch. A change to `envs/prod` in a dev PR is only planned and applied once it reaches `main`.

## Prod safety

- Ruleset on `dev`, `staging` and `main`: PR required, required checks, no force push, no deletion, merge commits only.
- `prod` GitHub environment: required reviewer, only deployable from `main`, no admin bypass.
- The apply role in AWS trusts only that GitHub environment.
- The plan that was reviewed is the plan that gets applied (saved as an artifact).
- PR plans use a read-only role and `-lock=false`.
- One apply at a time per env (concurrency group), never cancelled.
- Prod has EC2 termination protection, no `force_destroy` on the bucket, versioning on.
- The AMI is ignored after creation so a new Amazon Linux release doesn't replace the instance.

With a team I would also require 1-2 approvals on PRs and turn on "Require review from Code Owners".
I'm the only user here, so approvals are set to 0 and the reviewer on the prod environment is the gate.

## S3

Public access fully blocked, ACLs off, encrypted, versioning, policy that denies non-TLS requests.
The instance role can only touch that one bucket. The instance has no inbound rules, no ssh,
access goes through SSM. IMDSv2 only, encrypted root volume.

## Setup

1. Run bootstrap once per environment (it needs admin credentials, run from a laptop or a jump host):

       cd bootstrap
       terraform init
       terraform apply -state=dev.tfstate \
         -var environment=dev -var org_prefix=barba \
         -var github_repo=ORG/REPO

   For staging and prod add `-var create_oidc_provider=false`, the provider is created only once per account.
   Keep the `*.tfstate` files somewhere safe, they are not committed.

   Note: my GitHub org uses a custom OIDC `sub` claim that includes numeric ids
   (`repo:ORG@<org id>/REPO@<repo id>:...`). If yours does too, pass the prefix with
   `-var github_sub_prefix="repo:ORG@<org id>/REPO@<repo id>"`. You can see the real value
   by printing the `sub` claim in a workflow run. For a default org leave it empty.

2. In GitHub:
   - repo variables: `PLAN_ROLE_ARN_DEV`, `PLAN_ROLE_ARN_STAGING`, `PLAN_ROLE_ARN_PROD`
   - environments `dev`, `staging`, `prod`, each with variable `AWS_APPLY_ROLE_ARN`
   - reviewer and deployment branch on each environment (prod: branch `main`, reviewer required)
   - ruleset for `dev`, `staging`, `main`
3. Bucket names are global, if `barba-demo-<env>-data` is taken change `project` in `envs/*/variables.tf`.

## Running locally

    export AWS_PROFILE=<your profile>
    terraform fmt -recursive
    terraform -chdir=envs/dev init
    terraform -chdir=envs/dev plan

Only plan locally. Apply goes through the pipeline.

## Running through CI/CD

Open a PR, check the plan comment, merge. Promote with the next PR. For prod, approve the
deployment under Actions -> run -> Review deployments.

## Shortcuts / not done

- single AWS account for all three envs
- default VPC
- apply role is AdministratorAccess, should be scoped down
- no drift detection (a scheduled `plan -detailed-exitcode` per env would do it)
- actions are pinned by tag, not by commit SHA
