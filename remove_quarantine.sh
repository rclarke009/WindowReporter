#!/bin/bash

# Remove quarantine attributes from all files in the app bundle
# This prevents TestFlight/App Store submission errors

echo "Removing quarantine attributes from app resources..."

# Find all files in the WindowReporter directory and remove quarantine attributes
find "${SRCROOT}/WindowReporter" -type f -exec xattr -d com.apple.quarantine {} \; 2>/dev/null

# Also check and clean the built app bundle if it exists
if [ -d "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app" ]; then
    echo "Cleaning quarantine attributes from built app bundle..."
    find "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app" -type f -exec xattr -d com.apple.quarantine {} \; 2>/dev/null
fi

echo "Quarantine attribute removal complete."

