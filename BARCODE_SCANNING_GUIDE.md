# Barcode Scanning Feature - Implementation Guide

## ✅ Implementation Complete

Barcode scanning functionality has been successfully added to HealthBar. Users can now scan product barcodes to automatically retrieve nutrition information from the Open Food Facts database.

## 📁 Files Created/Modified

### New Files Created:
1. **Models/OpenFoodFactsModels.swift**
   - API response models for Open Food Facts
   - `OpenFoodFactsResponse`, `OpenFoodFactsProduct`, `OpenFoodFactsNutriments`
   - `FoodNutrition` - simplified nutrition data
   - `BarcodeError` - error handling enum
   - Mock data for previews

2. **Nutrition/BarcodeService.swift**
   - Service class for API integration
   - `fetchNutrition(barcode:)` - fetches from Open Food Facts
   - `calculateToxinScore()` - computes toxin score from Nova group, nutrition grade, and additives
   - Handles network requests, JSON parsing, and error handling

3. **UI/BarcodeScannerView.swift**
   - Full-screen camera scanner using AVFoundation
   - Detects UPC-A, UPC-E, EAN-13, EAN-8, and Code 128 barcodes
   - Visual scanning frame overlay
   - Haptic feedback on successful scan
   - Auto-dismisses after detection

4. **BARCODE_SCANNING_GUIDE.md** (this file)
   - Usage instructions and testing guide

### Files Modified:
1. **UI/FoodLogViewModel.swift**
   - Added `BarcodeService` dependency
   - Added barcode state properties:
     - `showingBarcodeScanner: Bool`
     - `scannedBarcode: String?`
     - `isLoadingBarcodeNutrition: Bool`
     - `barcodeError: String?`
   - Added `handleBarcodeScanned()` - processes scanned barcodes
   - Updated `addFoodEntry()` to accept `barcodeUPC` parameter
   - Updated `submitForm()` to include barcode in saved entry
   - Updated `resetForm()` to clear barcode state

2. **UI/AddFoodFormView.swift**
   - Added barcode scan button section below photo capture
   - Shows loading indicator while fetching nutrition
   - Displays error messages if barcode lookup fails
   - Shows success message with scanned barcode number
   - Added `.fullScreenCover` for barcode scanner presentation
   - Disabled save button while loading barcode nutrition

3. **--Info.plist**
   - Added `NSCameraUsageDescription` key for camera permissions
   - Description: "HealthBar needs camera access to photograph your meals and scan product barcodes for quick nutrition logging."

## 🎯 How It Works

### User Flow (Camera Scanning):
1. User taps "Log Food" button in Food Log tab
2. AddFoodFormView opens
3. User taps "Scan Barcode" button
4. Camera scanner opens full-screen with scanning frame
5. User points camera at product barcode
6. Barcode detected → haptic feedback → camera dismisses
7. "Looking up nutrition..." loading indicator appears
8. API fetches product data from Open Food Facts
9. Form auto-fills with nutrition data:
   - Product name
   - Calories (per 100g)
   - Protein, Carbs, Fat (per 100g)
   - Toxin score (calculated from Nova group + nutrition grade)
10. User can review/edit values before saving
11. User taps "Save Meal" → entry saved with both photo (if taken) AND barcode

### User Flow (Manual Entry):
1. User taps "Log Food" button in Food Log tab
2. AddFoodFormView opens
3. User taps "Enter Barcode Manually" button
4. Manual entry sheet opens with number pad
5. User enters barcode number (or taps example barcode to auto-fill)
6. User taps "Look Up Nutrition"
7. Sheet dismisses → "Looking up nutrition..." loading indicator appears
8. API fetches product data (same as camera flow)
9. Form auto-fills with nutrition data
10. User can review/edit values before saving
11. User taps "Save Meal" → entry saved with barcode

### Data Storage:
- Photo and barcode are stored separately
- An entry can have:
  - Photo only (user took picture, no barcode)
  - Barcode only (user scanned product, no photo)
  - Both photo AND barcode (user scanned product and took photo)
  - Neither (manual entry)

## 🧪 Testing Instructions

### ⚠️ IMPORTANT: Nutrition Data is Per 100g

**All nutrition values from Open Food Facts are standardized per 100g**, NOT per serving!

- If a product shows 400 calories, that's per 100g
- If you ate 50g, you consumed 200 calories
- **Users must manually adjust** for their actual portion size
- This is a limitation of using standardized nutrition databases

### Test Barcodes:

**Best approach**: Use any product you have at home and scan its barcode!

If you want to test without physical products, try these (results may vary by region):

1. **3017620422003** - Nutella (European, widely available)
   - Per 100g: ~550 cal, 6.3g protein, 57g carbs, 31g fat

2. **5000159484695** - Heinz Tomato Ketchup
   - Per 100g: ~100 cal, 1g protein, 23g carbs, 0g fat

3. **0016000275300** - Pop-Tarts (if available in your region)
   - Per 100g: varies by flavor

**Note**: Barcode databases vary by region and product availability. If a barcode doesn't work, the product may not be in the database yet.

### Manual Testing Steps:

1. **Build and Run the App**
   ```bash
   # Make sure camera permissions are granted on first launch
   ```

2. **Test Camera Barcode Scanning**
   - Navigate to Food Log tab
   - Tap floating "+" button
   - Tap "Scan Barcode" button
   - Grant camera permission if prompted
   - Point camera at one of the test barcodes above (or print them)
   - Verify barcode is detected and camera dismisses
   - Verify "Looking up nutrition..." appears
   - Verify form auto-fills with product data
   - Check that product name, calories, macros, and toxin score are populated

3. **Test Manual Barcode Entry (Easier for Testing!)**
   - Navigate to Food Log tab
   - Tap floating "+" button
   - Tap "Enter Barcode Manually" button
   - Enter one of the test barcodes (e.g., 737628064502)
   - OR tap one of the example barcodes to auto-fill
   - Tap "Look Up Nutrition"
   - Verify sheet dismisses
   - Verify "Looking up nutrition..." appears
   - Verify form auto-fills with product data
   - Check that product name, calories, macros, and toxin score are populated

4. **Test Error Handling**
   - Use manual entry to enter an invalid barcode (e.g., "123")
   - Tap "Look Up Nutrition"
   - Verify error message appears: "Product not found in database..."
   - Verify user can still manually enter data

5. **Test Network Error Handling**
   - Turn off WiFi/cellular
   - Use manual entry to enter a valid barcode
   - Tap "Look Up Nutrition"
   - Verify error message appears about network error

6. **Test Save with Barcode**
   - Manually enter or scan a valid barcode
   - Optionally take a photo as well
   - Edit any values if needed
   - Tap "Save Meal"
   - Verify entry is saved
   - Check that entry shows in today's meals list

7. **Test Clear Barcode**
   - Manually enter or scan a barcode
   - Verify "Scanned: [barcode]" appears
   - Tap "Clear" button
   - Verify barcode data is cleared
   - Verify form fields remain (not cleared)

## 🔧 API Details

### Open Food Facts API
- **Endpoint**: `https://world.openfoodfacts.org/api/v0/product/{barcode}.json`
- **No API key required** for basic usage
- **Free and open database** of food products
- **Coverage**: Worldwide, 2+ million products

### Response Format:
```json
{
  "status": 1,
  "product": {
    "product_name": "Example Product",
    "nutriments": {
      "energy-kcal_100g": 400,
      "proteins_100g": 20.0,
      "carbohydrates_100g": 50.0,
      "fat_100g": 14.0
    },
    "nutrition_grades": "b",
    "nova_group": 3,
    "additives_tags": ["en:e300", "en:e322"]
  }
}
```

## 📊 Toxin Score Calculation

The toxin score (0-100, lower is better) is calculated based on:

1. **Nova Group** (primary factor):
   - Nova 1 (unprocessed): base score 10
   - Nova 2 (processed ingredients): base score 30
   - Nova 3 (processed foods): base score 50
   - Nova 4 (ultra-processed): base score 70

2. **Nutrition Grade** (adjustment):
   - Grade A: -10 points
   - Grade B: -5 points
   - Grade C: 0 points
   - Grade D: +5 points
   - Grade E: +10 points

3. **Additives Count**:
   - Each additive: +2 points (max +20)

Final score is clamped to 0-100 range.

## 🎨 Design Integration

The barcode scanner UI follows the DesignSystem:
- **Colors**: Uses `DesignSystem.Colors.secondary` (emerald green) for barcode icon
- **Scanning frame**: Green outline matching brand colors
- **Loading states**: Consistent with existing app patterns
- **Error messages**: Uses warning color for visibility
- **Success states**: Green checkmark with primary color

## 🔐 Permissions

The app requires camera access for:
1. Taking photos of meals (existing feature)
2. Scanning product barcodes (new feature)

Both use the same `NSCameraUsageDescription` permission string.

## 🐛 Known Limitations

1. **⚠️ PER 100g NUTRITION (IMPORTANT!)**:
   - **API returns nutrition per 100g, NOT per serving**
   - A product showing 400 calories = 400 cal per 100g
   - Users MUST manually calculate their portion:
     - Ate 50g? Divide by 2 → 200 calories
     - Ate 150g? Multiply by 1.5 → 600 calories
   - **UI now shows warning label**: "(per 100g from barcode)"
   - Future enhancement: Add serving size multiplier field

2. **Product Coverage & Accuracy**:
   - Database has 2M+ products but not complete
   - Some products may not be found
   - **Barcodes can vary by region** (same product, different codes in different countries)
   - Product data is crowdsourced - may have errors
   - Users can always fall back to manual entry

3. **Network Dependency**:
   - Requires internet connection to fetch data
   - No offline barcode lookup (could cache frequently scanned products in future)

4. **Barcode Types**:
   - Currently supports: UPC-A, UPC-E, EAN-13, EAN-8, Code 128
   - Most food products use these formats

## 🚀 Future Enhancements

Potential improvements for later phases:
- Serving size multiplier for accurate portions
- Cache frequently scanned products for offline use
- Show product image from API in form
- "Scan to log again" - quick re-log of previously scanned items
- Barcode history/favorites
- Crowdsourced corrections for inaccurate data
- Support for QR codes with nutrition info

## ✅ Testing Checklist

- [ ] Build project successfully
- [ ] **Manual Entry (Testing)**
  - [ ] Manual barcode entry sheet opens
  - [ ] Number pad keyboard appears
  - [ ] Example barcodes are clickable and auto-fill
  - [ ] "Look Up Nutrition" button works
  - [ ] Sheet dismisses after submission
- [ ] **Camera Scanning**
  - [ ] Camera permission prompt appears on first use
  - [ ] Barcode scanner opens and shows camera preview
  - [ ] Scanning frame is visible and positioned correctly
  - [ ] Barcode detection works with test barcodes
  - [ ] Haptic feedback occurs on successful scan
  - [ ] Camera dismisses after successful scan
- [ ] **API Integration**
  - [ ] Loading indicator appears while fetching nutrition
  - [ ] Form auto-fills with correct product data
  - [ ] Toxin score is calculated correctly
  - [ ] Error message displays for invalid/missing products
  - [ ] Network error handling works (test offline)
- [ ] **Save & Clear**
  - [ ] Can save entry with barcode
  - [ ] Can save entry with both barcode AND photo
  - [ ] Clear button removes barcode but keeps form data
  - [ ] Save button is disabled while loading barcode data

## 📝 Architecture Compliance

This implementation follows the HealthBar architecture:

✅ **MVVM Pattern**: View → ViewModel → AppCoordinator → Managers
✅ **Separation of Concerns**: BarcodeService handles API, ViewModel manages state
✅ **No Direct Persistence**: ViewModel calls AppCoordinator, not DataManager
✅ **Clean Architecture**: New feature integrated without modifying core models
✅ **Observable Pattern**: Uses @Observable for reactive UI updates
✅ **Error Handling**: Proper error types and user-friendly messages

---

**Status**: ✅ Ready for Testing
**Next Steps**: Build and test with sample barcodes
