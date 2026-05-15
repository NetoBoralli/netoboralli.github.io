---
name: enhance-code
description: Scan the code staged in git and search for any bugs, unhandled edge cases, performance issues and opportunities for improvement such as making the code more idiomatic, more elegant, less repetitive, following DRY and YAGNI philosophies when it makes sense, turning magic strings into constants.
---

# Enhance Code

Analyze all staged changes and identify opportunities to improve code quality, correctness, and maintainability.

## Process

1. **Get staged changes**: Run `git diff --staged` to see all code being committed
2. **REQUIRED — Invoke specialized skills**: Before any analysis, check staged file types:
   - If ANY `.tsx`, `.jsx` files or JSX/React patterns are present: you MUST invoke `/vercel-react-best-practices` FIRST. Do NOT proceed to step 3 until this skill has been invoked and its guidelines applied.
   - This covers: re-render optimization, bundle size, server components, data fetching patterns
3. **Analyze each file**: Review changes for the categories below (general code quality: DRY, bugs, edge cases, etc.)
4. **Report findings**: Present issues grouped by severity and category
5. **Fix issues**: After presenting findings, fix each issue one by one

## Analysis Categories

### Bugs & Correctness
- Logic errors and off-by-one mistakes
- Null/undefined access without guards
- Race conditions in async code
- Incorrect error handling or swallowed exceptions
- Type mismatches or unsafe casts

### Unhandled Edge Cases
- Empty arrays/objects not handled
- Missing validation for user input
- Network failure scenarios
- Boundary conditions (max/min values)
- Concurrent modification scenarios

### Performance Issues
- Inefficient data structures or algorithms
- Missing memoization for expensive computations
- Redundant computations or API calls

### Code Quality Improvements
- **DRY violations**: Duplicated logic that should be extracted
- **Magic strings/numbers**: Hardcoded values that should be constants
- **Idiomatic patterns**: Code that could use language/framework conventions
- **Readability**: Overly complex expressions that could be simplified
- **Naming**: Variables or functions with unclear names

### YAGNI Violations
- Over-engineered abstractions
- Unused parameters or options
- Premature optimization
- Features or flexibility not currently needed

## Output Format

Group findings by file, then by severity:

**Critical** - Bugs that will cause runtime errors or incorrect behavior
**Warning** - Edge cases or potential issues under certain conditions
**Suggestion** - Improvements that enhance quality but aren't blocking

For each finding:
1. File and line reference
2. Brief description of the issue
3. Recommended fix

## Example Output

### `src/components/PaymentForm.tsx`

**Critical:**
- Line 45: Division by zero possible when `items.length === 0`
  - Add guard: `const avg = items.length > 0 ? total / items.length : 0`

**Warning:**
- Line 78: API error response not handled, will show undefined to user
  - Add error state handling in catch block

**Suggestion:**
- Lines 12, 34, 56: Status strings "pending", "completed" repeated
  - Extract to `PAYMENT_STATUS` constant object
