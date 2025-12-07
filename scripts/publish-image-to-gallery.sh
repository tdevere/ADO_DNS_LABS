#!/usr/bin/env zsh
set -euo pipefail

# Publishes the Lab 3 managed image to an Azure Compute Gallery and shares it.
# Requirements: az CLI logged in, Contributor on image RG.
# Usage:
#   ./scripts/publish-image-to-gallery.sh \
#      --image-id "/subscriptions/.../resourceGroups/rg.../providers/Microsoft.Compute/images/dns-server-lab3-bind9" \
#      --gallery-name DNSLabGallery \
#      --gallery-rg rg-dns-lab-images-20251129022831 \
#      --image-def dns-server-bind9 \
#      --publisher "DNSLab" \
#      --offer "CustomDNS" \
#      --sku "Lab3" \
#      --version "1.0.0" \
#      [--share community|none] \
#      [--target-subscriptions subId1,subId2]
#
# Notes:
# - Hyper-V generation set to V1 (Gen1) per lab build constraints.
# - Sharing options:
#   * community: enables community sharing (public browseable)
#   * none: no public sharing; optionally grant RBAC to specific subscriptions
# - If --target-subscriptions provided, assigns Reader on gallery to those subs using tenant scope role assignment.

function usage() {
  echo "Usage: $0 --image-id <id> --gallery-name <name> --gallery-rg <rg> --image-def <def> --publisher <pub> --offer <offer> --sku <sku> --version <ver> [--share community|none] [--target-subscriptions sub1,sub2]" >&2
}

# Defaults
SHARE_MODE="none"
TARGET_SUBS=""

zparseopts -D -E \
  -image-id:=IMAGE_ID \
  -gallery-name:=GALLERY_NAME \
  -gallery-rg:=GALLERY_RG \
  -image-def:=IMAGE_DEF \
  -publisher:=PUBLISHER \
  -offer:=OFFER \
  -sku:=SKU \
  -version:=VERSION \
  -share:=SHARE_MODE_OPT \
  -target-subscriptions:=TARGET_SUBS_OPT || { usage; exit 1 }

IMAGE_ID=${IMAGE_ID[2]:-}
GALLERY_NAME=${GALLERY_NAME[2]:-}
GALLERY_RG=${GALLERY_RG[2]:-}
IMAGE_DEF=${IMAGE_DEF[2]:-}
PUBLISHER=${PUBLISHER[2]:-}
OFFER=${OFFER[2]:-}
SKU=${SKU[2]:-}
VERSION=${VERSION[2]:-}

if [[ -n ${SHARE_MODE_OPT-} ]]; then SHARE_MODE=${SHARE_MODE_OPT[2]}; fi
if [[ -n ${TARGET_SUBS_OPT-} ]]; then TARGET_SUBS=${TARGET_SUBS_OPT[2]}; fi

if [[ -z "$IMAGE_ID$GALLERY_NAME$GALLERY_RG$IMAGE_DEF$PUBLISHER$OFFER$SKU$VERSION" ]]; then
  usage; exit 1
fi

echo "Creating/ensuring gallery $GALLERY_NAME in $GALLERY_RG..."
az sig create --resource-group "$GALLERY_RG" --gallery-name "$GALLERY_NAME" --location $(az group show -n "$GALLERY_RG" --query location -o tsv) --tags lab=DNS || true

echo "Creating/ensuring image definition $IMAGE_DEF..."
az sig image-definition create \
  --resource-group "$GALLERY_RG" \
  --gallery-name "$GALLERY_NAME" \
  --gallery-image-definition "$IMAGE_DEF" \
  --publisher "$PUBLISHER" \
  --offer "$OFFER" \
  --sku "$SKU" \
  --os-type Linux \
  --hyper-v-generation V1 || true

echo "Publishing version $VERSION from managed image..."
az sig image-version create \
  --resource-group "$GALLERY_RG" \
  --gallery-name "$GALLERY_NAME" \
  --gallery-image-definition "$IMAGE_DEF" \
  --gallery-image-version "$VERSION" \
  --managed-image "$IMAGE_ID" \
  --replica-count 1 \
  --target-regions $(az group show -n "$GALLERY_RG" --query location -o tsv) \
  --storage-account-type Standard_LRS

if [[ "$SHARE_MODE" == "community" ]]; then
  echo "Enabling community sharing (public)."
  az sig share enable-community --gallery-name "$GALLERY_NAME" --resource-group "$GALLERY_RG"
else
  echo "Community sharing not enabled."
fi

if [[ -n "$TARGET_SUBS" ]]; then
  echo "Granting Reader role to target subscriptions on the gallery..."
  IFS=',' read -r -A subs <<< "$TARGET_SUBS"
  GALLERY_ID=$(az sig show -g "$GALLERY_RG" -r "$GALLERY_NAME" --query id -o tsv)
  for sid in ${subs[@]}; do
    az role assignment create --assignee "${sid}" --role Reader --scope "$GALLERY_ID" || true
  done
fi

echo "Done. Students can consume via Azure Compute Gallery."
