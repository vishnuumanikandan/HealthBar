//
//  FoodDatabase.swift
//  HealthBar
//
//  Created by Claude on 3/29/26.
//

import Foundation

// MARK: - BuiltInFood

/// A hardcoded ingredient from the built-in food library.
///
/// Nutrition values represent the base serving (e.g., 100g, 1 egg).
/// The ServingSizePickerSheet scales these values by (quantity / baseAmount).
struct BuiltInFood: Identifiable, Hashable {
    let id: UUID
    let name: String
    /// Calories for the base serving
    let calories: Int
    /// Protein (g) for the base serving
    let protein: Double
    /// Carbs (g) for the base serving
    let carbs: Double
    /// Fat (g) for the base serving
    let fat: Double
    /// Human-readable label shown in the picker (e.g., "100g", "1 large", "1 cup")
    let servingDescription: String
    /// The numeric denominator for scaling (e.g., 100 for "100g", 1 for "1 egg")
    let baseAmount: Double
    /// The unit label shown beside the quantity field (e.g., "g", "egg", "cup")
    let unit: String

    /// Scales nutrition to the given quantity
    func scaled(to quantity: Double) -> (calories: Int, protein: Double, carbs: Double, fat: Double) {
        let factor = quantity / baseAmount
        return (
            calories: Int((Double(calories) * factor).rounded()),
            protein: protein * factor,
            carbs: carbs * factor,
            fat: fat * factor
        )
    }
}

// MARK: - LoggableFood

/// A unified food type used by ServingSizePickerSheet.
/// Created from a BuiltInFood, CustomFood, or any food source.
struct LoggableFood: Identifiable {
    let id: UUID
    let name: String
    let caloriesPerBase: Int
    let proteinPerBase: Double
    let carbsPerBase: Double
    let fatPerBase: Double
    let baseAmount: Double
    let unit: String
    let servingDescription: String
    let toxinScore: Int

    func scaled(to quantity: Double) -> (calories: Int, protein: Double, carbs: Double, fat: Double) {
        let factor = quantity / baseAmount
        return (
            calories: Int((Double(caloriesPerBase) * factor).rounded()),
            protein: proteinPerBase * factor,
            carbs: carbsPerBase * factor,
            fat: fatPerBase * factor
        )
    }

    // Convert from BuiltInFood
    init(from food: BuiltInFood) {
        self.id = food.id
        self.name = food.name
        self.caloriesPerBase = food.calories
        self.proteinPerBase = food.protein
        self.carbsPerBase = food.carbs
        self.fatPerBase = food.fat
        self.baseAmount = food.baseAmount
        self.unit = food.unit
        self.servingDescription = food.servingDescription
        self.toxinScore = 0
    }

    // Convert from CustomFood
    init(from food: CustomFood) {
        self.id = food.id
        self.name = food.name
        self.caloriesPerBase = food.calories
        self.proteinPerBase = food.protein
        self.carbsPerBase = food.carbs
        self.fatPerBase = food.fat
        self.baseAmount = food.servingSizeAmount
        self.unit = food.servingUnit
        self.servingDescription = food.servingSizeName
        self.toxinScore = food.toxinScore
    }

    // Convert from SavedRecipe (per-serving values, 1 serving = base amount)
    init(from recipe: SavedRecipe) {
        self.id = recipe.id
        self.name = recipe.name
        self.caloriesPerBase = recipe.perServingCalories
        self.proteinPerBase = recipe.perServingProtein
        self.carbsPerBase = recipe.perServingCarbs
        self.fatPerBase = recipe.perServingFat
        self.baseAmount = 1.0
        self.unit = "serving"
        self.servingDescription = "1 serving (\(recipe.yield) total)"
        self.toxinScore = 0
    }
}

// MARK: - Built-In Food Library

/// The hardcoded library of ~150 common ingredients.
/// Nutrition values are approximate and represent typical values per standard serving.
enum BuiltInFoods {
    static let all: [BuiltInFood] = [

        // MARK: Proteins – Meat & Poultry
        BuiltInFood(id: UUID(), name: "Chicken Breast", calories: 165, protein: 31, carbs: 0, fat: 3.6,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Ground Beef (80/20)", calories: 254, protein: 17, carbs: 0, fat: 20,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Turkey Breast", calories: 135, protein: 30, carbs: 0, fat: 1,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Pork Tenderloin", calories: 143, protein: 26, carbs: 0, fat: 3.5,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Chicken Thigh", calories: 209, protein: 26, carbs: 0, fat: 11,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Beef Steak (Sirloin)", calories: 207, protein: 26, carbs: 0, fat: 11,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Bacon", calories: 541, protein: 37, carbs: 1.4, fat: 42,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Ham", calories: 163, protein: 17, carbs: 5, fat: 8,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),

        // MARK: Proteins – Seafood
        BuiltInFood(id: UUID(), name: "Salmon (Atlantic)", calories: 208, protein: 20, carbs: 0, fat: 13,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Shrimp", calories: 99, protein: 24, carbs: 0.2, fat: 0.3,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Canned Tuna (in water)", calories: 109, protein: 25, carbs: 0, fat: 1,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Tilapia", calories: 96, protein: 20, carbs: 0, fat: 2,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Cod", calories: 82, protein: 18, carbs: 0, fat: 0.7,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Sardines (in oil)", calories: 208, protein: 25, carbs: 0, fat: 11,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),

        // MARK: Proteins – Eggs & Dairy
        BuiltInFood(id: UUID(), name: "Egg (large)", calories: 70, protein: 6, carbs: 0.6, fat: 5,
                    servingDescription: "1 egg", baseAmount: 1, unit: "egg"),
        BuiltInFood(id: UUID(), name: "Egg White", calories: 17, protein: 3.6, carbs: 0.2, fat: 0.1,
                    servingDescription: "1 white", baseAmount: 1, unit: "white"),
        BuiltInFood(id: UUID(), name: "Whole Milk", calories: 149, protein: 8, carbs: 11.7, fat: 8,
                    servingDescription: "1 cup (240ml)", baseAmount: 1, unit: "cup"),
        BuiltInFood(id: UUID(), name: "Skim Milk", calories: 83, protein: 8, carbs: 12, fat: 0.2,
                    servingDescription: "1 cup (240ml)", baseAmount: 1, unit: "cup"),
        BuiltInFood(id: UUID(), name: "Greek Yogurt (plain)", calories: 59, protein: 10, carbs: 3.6, fat: 0.4,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Cottage Cheese", calories: 98, protein: 11, carbs: 3.4, fat: 4.5,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Cheddar Cheese", calories: 403, protein: 25, carbs: 1.3, fat: 33,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Mozzarella Cheese", calories: 280, protein: 28, carbs: 2.2, fat: 17,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Parmesan Cheese", calories: 431, protein: 38, carbs: 4, fat: 29,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Butter", calories: 102, protein: 0.1, carbs: 0, fat: 11.5,
                    servingDescription: "1 tbsp (14g)", baseAmount: 14, unit: "g"),
        BuiltInFood(id: UUID(), name: "Heavy Cream", calories: 51, protein: 0.3, carbs: 0.4, fat: 5.5,
                    servingDescription: "1 tbsp", baseAmount: 1, unit: "tbsp"),

        // MARK: Proteins – Plant
        BuiltInFood(id: UUID(), name: "Tofu (firm)", calories: 76, protein: 8, carbs: 1.9, fat: 4.2,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Tempeh", calories: 193, protein: 19, carbs: 7.6, fat: 11,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Edamame", calories: 121, protein: 11, carbs: 8.9, fat: 5,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),

        // MARK: Grains & Starches
        BuiltInFood(id: UUID(), name: "White Rice (cooked)", calories: 130, protein: 2.7, carbs: 28, fat: 0.3,
                    servingDescription: "100g cooked", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Brown Rice (cooked)", calories: 112, protein: 2.3, carbs: 23, fat: 0.9,
                    servingDescription: "100g cooked", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Pasta (cooked)", calories: 131, protein: 5, carbs: 25, fat: 1.1,
                    servingDescription: "100g cooked", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Oats (dry)", calories: 389, protein: 17, carbs: 66, fat: 7,
                    servingDescription: "100g dry", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Oatmeal (cooked)", calories: 71, protein: 2.5, carbs: 12, fat: 1.5,
                    servingDescription: "100g cooked", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "White Bread", calories: 79, protein: 2.7, carbs: 15, fat: 1,
                    servingDescription: "1 slice (30g)", baseAmount: 30, unit: "g"),
        BuiltInFood(id: UUID(), name: "Whole Wheat Bread", calories: 69, protein: 3.6, carbs: 12, fat: 1.1,
                    servingDescription: "1 slice (30g)", baseAmount: 30, unit: "g"),
        BuiltInFood(id: UUID(), name: "Quinoa (cooked)", calories: 120, protein: 4.4, carbs: 21, fat: 1.9,
                    servingDescription: "100g cooked", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Corn Tortilla", calories: 52, protein: 1.4, carbs: 11, fat: 0.7,
                    servingDescription: "1 tortilla (26g)", baseAmount: 26, unit: "g"),
        BuiltInFood(id: UUID(), name: "Flour Tortilla", calories: 146, protein: 3.8, carbs: 25, fat: 3.5,
                    servingDescription: "1 medium (45g)", baseAmount: 45, unit: "g"),
        BuiltInFood(id: UUID(), name: "White Potato", calories: 77, protein: 2, carbs: 17, fat: 0.1,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Sweet Potato", calories: 86, protein: 1.6, carbs: 20, fat: 0.1,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Bagel (plain)", calories: 270, protein: 10, carbs: 53, fat: 1.7,
                    servingDescription: "1 bagel (105g)", baseAmount: 105, unit: "g"),

        // MARK: Vegetables
        BuiltInFood(id: UUID(), name: "Broccoli", calories: 34, protein: 2.8, carbs: 7, fat: 0.4,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Spinach", calories: 23, protein: 2.9, carbs: 3.6, fat: 0.4,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Kale", calories: 49, protein: 4.3, carbs: 8.8, fat: 0.9,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Romaine Lettuce", calories: 17, protein: 1.2, carbs: 3.3, fat: 0.3,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Arugula", calories: 25, protein: 2.6, carbs: 3.7, fat: 0.7,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Cucumber", calories: 16, protein: 0.7, carbs: 3.6, fat: 0.1,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Tomato", calories: 18, protein: 0.9, carbs: 3.9, fat: 0.2,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Bell Pepper (red)", calories: 31, protein: 1, carbs: 6, fat: 0.3,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Onion", calories: 40, protein: 1.1, carbs: 9.3, fat: 0.1,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Garlic", calories: 149, protein: 6.4, carbs: 33, fat: 0.5,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Mushrooms", calories: 22, protein: 3.1, carbs: 3.3, fat: 0.3,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Zucchini", calories: 17, protein: 1.2, carbs: 3.1, fat: 0.3,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Asparagus", calories: 20, protein: 2.2, carbs: 3.9, fat: 0.1,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Green Beans", calories: 31, protein: 1.8, carbs: 7, fat: 0.2,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Carrot", calories: 41, protein: 0.9, carbs: 10, fat: 0.2,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Celery", calories: 16, protein: 0.7, carbs: 3, fat: 0.2,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Cauliflower", calories: 25, protein: 1.9, carbs: 5, fat: 0.3,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Brussels Sprouts", calories: 43, protein: 3.4, carbs: 9, fat: 0.3,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Corn (kernels)", calories: 86, protein: 3.3, carbs: 19, fat: 1.2,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),

        // MARK: Fruits
        BuiltInFood(id: UUID(), name: "Banana", calories: 89, protein: 1.1, carbs: 23, fat: 0.3,
                    servingDescription: "1 medium (118g)", baseAmount: 118, unit: "g"),
        BuiltInFood(id: UUID(), name: "Apple", calories: 52, protein: 0.3, carbs: 14, fat: 0.2,
                    servingDescription: "1 medium (182g)", baseAmount: 182, unit: "g"),
        BuiltInFood(id: UUID(), name: "Orange", calories: 47, protein: 0.9, carbs: 12, fat: 0.1,
                    servingDescription: "1 medium (131g)", baseAmount: 131, unit: "g"),
        BuiltInFood(id: UUID(), name: "Grapes", calories: 69, protein: 0.7, carbs: 18, fat: 0.2,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Strawberries", calories: 32, protein: 0.7, carbs: 7.7, fat: 0.3,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Blueberries", calories: 57, protein: 0.7, carbs: 14, fat: 0.3,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Mango", calories: 60, protein: 0.8, carbs: 15, fat: 0.4,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Pineapple", calories: 50, protein: 0.5, carbs: 13, fat: 0.1,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Watermelon", calories: 30, protein: 0.6, carbs: 7.6, fat: 0.2,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Avocado", calories: 160, protein: 2, carbs: 9, fat: 15,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Pear", calories: 57, protein: 0.4, carbs: 15, fat: 0.1,
                    servingDescription: "1 medium (178g)", baseAmount: 178, unit: "g"),
        BuiltInFood(id: UUID(), name: "Peach", calories: 39, protein: 0.9, carbs: 10, fat: 0.3,
                    servingDescription: "1 medium (150g)", baseAmount: 150, unit: "g"),
        BuiltInFood(id: UUID(), name: "Lemon", calories: 29, protein: 1.1, carbs: 9.3, fat: 0.3,
                    servingDescription: "1 fruit (58g)", baseAmount: 58, unit: "g"),

        // MARK: Legumes & Beans
        BuiltInFood(id: UUID(), name: "Black Beans (cooked)", calories: 132, protein: 8.9, carbs: 24, fat: 0.5,
                    servingDescription: "100g cooked", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Chickpeas (cooked)", calories: 164, protein: 8.9, carbs: 27, fat: 2.6,
                    servingDescription: "100g cooked", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Lentils (cooked)", calories: 116, protein: 9, carbs: 20, fat: 0.4,
                    servingDescription: "100g cooked", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Kidney Beans (cooked)", calories: 127, protein: 8.7, carbs: 23, fat: 0.5,
                    servingDescription: "100g cooked", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Pinto Beans (cooked)", calories: 143, protein: 9, carbs: 27, fat: 0.6,
                    servingDescription: "100g cooked", baseAmount: 100, unit: "g"),

        // MARK: Nuts & Seeds
        BuiltInFood(id: UUID(), name: "Almonds", calories: 579, protein: 21, carbs: 22, fat: 50,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Walnuts", calories: 654, protein: 15, carbs: 14, fat: 65,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Cashews", calories: 553, protein: 18, carbs: 30, fat: 44,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Peanuts", calories: 567, protein: 26, carbs: 16, fat: 49,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Peanut Butter", calories: 588, protein: 25, carbs: 20, fat: 50,
                    servingDescription: "2 tbsp (32g)", baseAmount: 32, unit: "g"),
        BuiltInFood(id: UUID(), name: "Almond Butter", calories: 614, protein: 21, carbs: 19, fat: 56,
                    servingDescription: "2 tbsp (32g)", baseAmount: 32, unit: "g"),
        BuiltInFood(id: UUID(), name: "Chia Seeds", calories: 486, protein: 17, carbs: 42, fat: 31,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Flax Seeds", calories: 534, protein: 18, carbs: 29, fat: 42,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Sunflower Seeds", calories: 584, protein: 21, carbs: 20, fat: 51,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),

        // MARK: Fats & Oils
        BuiltInFood(id: UUID(), name: "Olive Oil", calories: 119, protein: 0, carbs: 0, fat: 13.5,
                    servingDescription: "1 tbsp (13.5g)", baseAmount: 13.5, unit: "g"),
        BuiltInFood(id: UUID(), name: "Coconut Oil", calories: 121, protein: 0, carbs: 0, fat: 13.6,
                    servingDescription: "1 tbsp (13.6g)", baseAmount: 13.6, unit: "g"),
        BuiltInFood(id: UUID(), name: "Avocado Oil", calories: 124, protein: 0, carbs: 0, fat: 14,
                    servingDescription: "1 tbsp (14g)", baseAmount: 14, unit: "g"),

        // MARK: Beverages
        BuiltInFood(id: UUID(), name: "Orange Juice", calories: 112, protein: 1.7, carbs: 26, fat: 0.5,
                    servingDescription: "1 cup (248ml)", baseAmount: 248, unit: "ml"),
        BuiltInFood(id: UUID(), name: "Apple Juice", calories: 117, protein: 0.1, carbs: 29, fat: 0.3,
                    servingDescription: "1 cup (248ml)", baseAmount: 248, unit: "ml"),
        BuiltInFood(id: UUID(), name: "Skim Latte (12oz)", calories: 120, protein: 12, carbs: 18, fat: 0,
                    servingDescription: "1 medium (355ml)", baseAmount: 355, unit: "ml"),
        BuiltInFood(id: UUID(), name: "Black Coffee", calories: 2, protein: 0.3, carbs: 0, fat: 0,
                    servingDescription: "1 cup (240ml)", baseAmount: 240, unit: "ml"),
        BuiltInFood(id: UUID(), name: "Green Tea", calories: 2, protein: 0.1, carbs: 0.5, fat: 0,
                    servingDescription: "1 cup (240ml)", baseAmount: 240, unit: "ml"),
        BuiltInFood(id: UUID(), name: "Protein Shake (whey, vanilla)", calories: 120, protein: 24, carbs: 5, fat: 1.5,
                    servingDescription: "1 scoop (30g)", baseAmount: 30, unit: "g"),

        // MARK: Condiments & Sauces
        BuiltInFood(id: UUID(), name: "Ketchup", calories: 20, protein: 0.3, carbs: 5, fat: 0,
                    servingDescription: "1 tbsp (17g)", baseAmount: 17, unit: "g"),
        BuiltInFood(id: UUID(), name: "Mustard (yellow)", calories: 10, protein: 0.5, carbs: 1, fat: 0.6,
                    servingDescription: "1 tbsp (15g)", baseAmount: 15, unit: "g"),
        BuiltInFood(id: UUID(), name: "Mayonnaise", calories: 94, protein: 0.1, carbs: 0.1, fat: 10.3,
                    servingDescription: "1 tbsp (14g)", baseAmount: 14, unit: "g"),
        BuiltInFood(id: UUID(), name: "Ranch Dressing", calories: 73, protein: 0.4, carbs: 1.2, fat: 7.5,
                    servingDescription: "1 tbsp (15g)", baseAmount: 15, unit: "g"),
        BuiltInFood(id: UUID(), name: "Hot Sauce", calories: 6, protein: 0.3, carbs: 1.2, fat: 0.1,
                    servingDescription: "1 tbsp", baseAmount: 1, unit: "tbsp"),
        BuiltInFood(id: UUID(), name: "Soy Sauce", calories: 8, protein: 0.9, carbs: 0.8, fat: 0,
                    servingDescription: "1 tbsp", baseAmount: 1, unit: "tbsp"),
        BuiltInFood(id: UUID(), name: "BBQ Sauce", calories: 29, protein: 0.2, carbs: 7, fat: 0,
                    servingDescription: "1 tbsp (17g)", baseAmount: 17, unit: "g"),
        BuiltInFood(id: UUID(), name: "Salsa", calories: 10, protein: 0.5, carbs: 2, fat: 0,
                    servingDescription: "2 tbsp", baseAmount: 2, unit: "tbsp"),
        BuiltInFood(id: UUID(), name: "Hummus", calories: 166, protein: 8, carbs: 14, fat: 10,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Guacamole", calories: 150, protein: 2, carbs: 8, fat: 13,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),

        // MARK: Snacks & Other
        BuiltInFood(id: UUID(), name: "Tortilla Chips", calories: 140, protein: 2, carbs: 19, fat: 7,
                    servingDescription: "1 oz (28g)", baseAmount: 28, unit: "g"),
        BuiltInFood(id: UUID(), name: "Potato Chips", calories: 152, protein: 2, carbs: 15, fat: 10,
                    servingDescription: "1 oz (28g)", baseAmount: 28, unit: "g"),
        BuiltInFood(id: UUID(), name: "Popcorn (air-popped)", calories: 31, protein: 1, carbs: 6.2, fat: 0.4,
                    servingDescription: "1 cup popped", baseAmount: 1, unit: "cup"),
        BuiltInFood(id: UUID(), name: "Dark Chocolate (70%)", calories: 170, protein: 2, carbs: 13, fat: 12,
                    servingDescription: "1 oz (28g)", baseAmount: 28, unit: "g"),
        BuiltInFood(id: UUID(), name: "Granola Bar", calories: 193, protein: 4, carbs: 29, fat: 7,
                    servingDescription: "1 bar (47g)", baseAmount: 47, unit: "g"),
        BuiltInFood(id: UUID(), name: "Rice Cake (plain)", calories: 35, protein: 0.7, carbs: 7.3, fat: 0.3,
                    servingDescription: "1 cake (9g)", baseAmount: 9, unit: "g"),

        // MARK: Breakfast Foods
        BuiltInFood(id: UUID(), name: "Pancake", calories: 86, protein: 2.3, carbs: 13, fat: 3,
                    servingDescription: "1 medium (38g)", baseAmount: 38, unit: "g"),
        BuiltInFood(id: UUID(), name: "Waffle", calories: 218, protein: 5.9, carbs: 25, fat: 10.6,
                    servingDescription: "1 waffle (75g)", baseAmount: 75, unit: "g"),
        BuiltInFood(id: UUID(), name: "Granola (dry)", calories: 471, protein: 10, carbs: 64, fat: 20,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Corn Flakes", calories: 357, protein: 7, carbs: 84, fat: 0.4,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Honey", calories: 64, protein: 0.1, carbs: 17, fat: 0,
                    servingDescription: "1 tbsp (21g)", baseAmount: 21, unit: "g"),
        BuiltInFood(id: UUID(), name: "Maple Syrup", calories: 52, protein: 0, carbs: 13, fat: 0,
                    servingDescription: "1 tbsp (20g)", baseAmount: 20, unit: "g"),
        BuiltInFood(id: UUID(), name: "Jam / Jelly", calories: 56, protein: 0.1, carbs: 14, fat: 0,
                    servingDescription: "1 tbsp (20g)", baseAmount: 20, unit: "g"),

        // MARK: Fast Food / Restaurant
        BuiltInFood(id: UUID(), name: "Hamburger (plain)", calories: 295, protein: 17, carbs: 24, fat: 14,
                    servingDescription: "1 burger", baseAmount: 1, unit: "burger"),
        BuiltInFood(id: UUID(), name: "Pizza Slice (cheese)", calories: 285, protein: 12, carbs: 36, fat: 10,
                    servingDescription: "1 slice", baseAmount: 1, unit: "slice"),
        BuiltInFood(id: UUID(), name: "French Fries (small)", calories: 230, protein: 3, carbs: 29, fat: 11,
                    servingDescription: "1 small order (71g)", baseAmount: 71, unit: "g"),
        BuiltInFood(id: UUID(), name: "Burrito (bean & cheese)", calories: 415, protein: 16, carbs: 56, fat: 14,
                    servingDescription: "1 burrito", baseAmount: 1, unit: "burrito"),

        // MARK: Sauces & Spreads
        BuiltInFood(id: UUID(), name: "Cream Cheese", calories: 342, protein: 6, carbs: 4.1, fat: 34,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Sour Cream", calories: 193, protein: 2.4, carbs: 4.6, fat: 19,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Whipped Cream", calories: 257, protein: 2.2, carbs: 12, fat: 22,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),

        // MARK: Miscellaneous Cooking Staples
        BuiltInFood(id: UUID(), name: "All-Purpose Flour", calories: 364, protein: 10, carbs: 76, fat: 1,
                    servingDescription: "100g", baseAmount: 100, unit: "g"),
        BuiltInFood(id: UUID(), name: "Sugar (white)", calories: 387, protein: 0, carbs: 100, fat: 0,
                    servingDescription: "1 tsp (4g)", baseAmount: 4, unit: "g"),
        BuiltInFood(id: UUID(), name: "Brown Sugar", calories: 380, protein: 0, carbs: 98, fat: 0,
                    servingDescription: "1 tsp (5g)", baseAmount: 5, unit: "g"),
        BuiltInFood(id: UUID(), name: "Baking Powder", calories: 2, protein: 0, carbs: 0.5, fat: 0,
                    servingDescription: "1 tsp (3g)", baseAmount: 3, unit: "g"),
        BuiltInFood(id: UUID(), name: "Salt", calories: 0, protein: 0, carbs: 0, fat: 0,
                    servingDescription: "1 tsp", baseAmount: 1, unit: "tsp"),
        BuiltInFood(id: UUID(), name: "White Vinegar", calories: 3, protein: 0, carbs: 0.5, fat: 0,
                    servingDescription: "1 tbsp", baseAmount: 1, unit: "tbsp"),
        BuiltInFood(id: UUID(), name: "Lemon Juice", calories: 4, protein: 0.1, carbs: 1.3, fat: 0,
                    servingDescription: "1 tbsp", baseAmount: 1, unit: "tbsp"),
    ]
}
