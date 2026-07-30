/**
 * AIPROXY-1a — frozen prompt text.
 *
 * Every string here is copied BYTE-IDENTICALLY from the shipping Swift client.
 * The prompts live server-side so the client can never assemble, override, or
 * inspect them; they are never logged, never returned in a callable response,
 * and never placed in an HttpsError message or details payload.
 *
 * DO NOT edit for tone, wording, or whitespace. Prompt text is behavior: an
 * edit here silently changes AI output for every user. Any change must be its
 * own prompt with its own eval, and must be mirrored in the Swift source until
 * AIPROXY-1b retires the client-side copies.
 *
 * Sources (line numbers are the AIPROXY-1a base commit, 6f840da):
 *   Nutrition/AIFoodRecognitionService.swift:216      imageOnlyPrompt
 *   Nutrition/AIFoodRecognitionService.swift:220      systemPromptGeneral
 *   Nutrition/AIFoodRecognitionService.swift:223-239  systemPromptSchemaOnward
 *   Nutrition/AIFoodRecognitionService.swift:241-243  imageReconciliationRule
 *   UI/OnboardingViewModel.swift:402-407              callClaudeAPI systemPrompt
 */

/**
 * The general instruction that leads every recognition request.
 * Swift: AIFoodRecognitionService.systemPromptGeneral
 */
const SYSTEM_PROMPT_GENERAL = 'Return ONLY a JSON object, no prose, no markdown fences.';

/**
 * Schema description -> example -> units -> toxin-scoring -> clarification rules.
 *
 * The Swift literal is a multiline string in which EVERY line ends with a
 * backslash continuation, so the value contains NO newlines. Each concatenated
 * piece below is one Swift source line, in order, so the two can be diffed
 * side by side.
 *
 * Swift: AIFoodRecognitionService.systemPromptSchemaOnward
 */
const SYSTEM_PROMPT_SCHEMA_ONWARD =
  'Schema:' +
  '{"items":[{"name":String,"quantity":String,"calories":Int,"protein":Number,"carbs":Number,"fat":Number,"toxinScore":Int,"fiber":Number|null,"sugar":Number|null,"sodium":Number|null,"saturatedFat":Number|null,"cholesterol":Number|null,"potassium":Number|null,"confidence":"high"|"medium"|"low","confidenceReason":String|null}],' +
  '"clarification":String|null,' +
  '"clarifications":[{"itemIndex":Int,"question":String,"importance":Number,"defaultOptionIndex":Int,"options":[{"label":String,"dCalories":Int,"dProtein":Number,"dCarbs":Number,"dFat":Number}]}]}' +
  'Example: "2 scrambled eggs, toast" → {"items":[{"name":"Scrambled Eggs","quantity":"2 eggs","calories":182,"protein":12.6,"carbs":1.6,"fat":13.6,"toxinScore":10,"fiber":0,"sugar":0.6,"sodium":180,"saturatedFat":4.1,"cholesterol":372,"potassium":176,"confidence":"high","confidenceReason":null},{"name":"Toast","quantity":"1 slice","calories":79,"protein":2.7,"carbs":14.7,"fat":1.0,"toxinScore":40,"fiber":1.9,"sugar":1.5,"sodium":150,"saturatedFat":0.2,"cholesterol":0,"potassium":50,"confidence":"medium","confidenceReason":null}],"clarification":null,"clarifications":[]}' +
  'Units: fiber/sugar/saturatedFat in grams; sodium/cholesterol/potassium in milligrams. Omit (null) any micronutrient you cannot reasonably estimate for this specific food — never guess sodium/cholesterol/potassium for foods where it is highly variable.' +
  'toxinScore rates how processed/unhealthy the item is, 0–100: 0–15 whole unprocessed foods (fruits, vegetables, plain meats, eggs, plain grains); 16–35 lightly processed (plain yogurt, whole-grain bread, cheese, home-cooked mixed dishes); 36–60 moderately processed (white bread, deli meat, granola bars, restaurant meals with unknown oils); 61–85 ultra-processed (chips, candy, soda, fast food); 86–100 extreme (energy drinks with candy, deep-fried ultra-processed combinations). Score the item as described, not a worst-case version of it.' +
  'Set confidence:"low" when portion or identity is uncertain. If input is too vague to estimate any items, return {"items":[],"clarification":"<your question>","clarifications":[]}.' +
  'Emit clarifications ONLY for genuinely ambiguous items — unknown portion, likely-hidden added fats (oil/butter/dressing/sauce), or ambiguous size. High-confidence items get none.' +
  'Max 3 clarifications total; max 4 options each; options mutually exclusive; labels ≤14 chars.' +
  'Each option\'s deltas are relative to that item\'s returned baseline macros. Exactly one option per question is the default (defaultOptionIndex) with all-zero deltas.' +
  'Set importance per clarification by expected calorie swing: portion of staples, added oil/butter, dressing, sauce score high; herbs, lettuce, spices, garnishes score low.' +
  'Provide confidenceReason for every non-high-confidence item — the single biggest source of uncertainty.' +
  'Each option\'s deltas must stay within ±2000 calories and ±250g per macro.' +
  'Option deltas must be nutritionally plausible: calorie delta ≈ P·4 + C·4 + F·9. Do not return calorie-only deltas with zero macro change.';

/**
 * Appended to the system prompt only on the photo path. Note the intentional
 * LEADING SPACE — the Swift literal is indented one space past its closing
 * delimiter so it joins onto the preceding sentence.
 *
 * Swift: AIFoodRecognitionService.imageReconciliationRule
 */
const IMAGE_RECONCILIATION_RULE =
  ' When both text and image are provided: prefer the text for food identity when they conflict; use the image to estimate portion/quantity and to include clearly visible foods the text omitted. Return ONLY the JSON object.';

/**
 * The user-turn text sent alongside the image when the client supplies no
 * description. AILOG-1a: composeStructuredInput falls back to this whenever
 * there is no text and no structured field.
 *
 * Swift: AIFoodRecognitionService.imageOnlyPrompt
 */
export const IMAGE_ONLY_USER_PROMPT = 'Identify the foods in this image and estimate their nutrition.';

/**
 * System prompt for the text describe path.
 *
 * Assembled exactly as buildSystemPromptBase(category: nil) does — general,
 * a single space, then the schema block. The proxy never takes a category, so
 * the no-category branch is the only one reachable and the result is
 * byte-identical to what the client sends today.
 */
export const DESCRIBE_MEAL_SYSTEM_PROMPT =
  SYSTEM_PROMPT_GENERAL + ' ' + SYSTEM_PROMPT_SCHEMA_ONWARD;

/**
 * System prompt for the photo recognition path: the describe prompt plus the
 * image reconciliation rule, matching the Swift multimodal branch
 * (buildSystemPromptBase(category:) + imageReconciliationRule).
 */
export const PHOTO_RECOGNITION_SYSTEM_PROMPT =
  DESCRIBE_MEAL_SYSTEM_PROMPT + IMAGE_RECONCILIATION_RULE;

/**
 * System prompt for onboarding goal personalisation. Unlike the recognition
 * prompt this Swift literal has NO line continuations, so the value keeps a
 * newline between each of its four lines.
 *
 * Swift: OnboardingViewModel.callClaudeAPI systemPrompt
 */
export const ONBOARDING_GOALS_SYSTEM_PROMPT =
  'You are a concise nutrition coach. Return ONLY a JSON object, no prose, no markdown fences.\n' +
  '{"calories": Int, "protein": Int, "carbs": Int, "fat": Int, "tip": String}\n' +
  'tip must be exactly 2 sentences, personalized to the user\'s profile.\n' +
  'Honor goalDirection: for "maintain" keep calories within 5% of formulaCalories; never assume the user wants weight loss.';
