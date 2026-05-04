```markdown
# solo-compass Development Patterns

> Auto-generated skill from repository analysis

## Overview
This skill teaches you the core development patterns and conventions used in the `solo-compass` Swift codebase. You'll learn about file naming, import/export styles, commit message conventions, and how to write and run tests. While no automated workflows were detected, this guide provides suggested commands and step-by-step instructions for common development tasks.

## Coding Conventions

### File Naming
- Use **PascalCase** for all file names.
  - Example: `LocationManager.swift`, `CompassView.swift`

### Import Style
- Use **relative imports** within the project.
  - Example:
    ```swift
    import Foundation
    import ../Utilities/MathHelpers
    ```

### Export Style
- Use **named exports** for classes, structs, and functions.
  - Example:
    ```swift
    public class CompassView: UIView {
        // ...
    }
    ```

### Commit Message Conventions
- Use **conventional commit** types.
- Supported prefixes: `chore`, `fix`
- Keep commit messages concise (average ~50 characters).
  - Example:
    ```
    fix: correct heading calculation in CompassView
    chore: update dependencies to latest version
    ```

## Workflows

### Creating a New Feature
**Trigger:** When adding a new feature or component  
**Command:** `/create-feature`

1. Create a new Swift file using PascalCase (e.g., `NewFeature.swift`).
2. Use relative imports for dependencies.
3. Export your class/struct/function using named exports.
4. Write or update tests in a corresponding `*.test.*` file.
5. Commit your changes using a conventional commit message.

### Fixing a Bug
**Trigger:** When addressing a bug or issue  
**Command:** `/fix-bug`

1. Identify the file(s) where the bug exists.
2. Make the necessary code changes.
3. Update or add tests in the relevant `*.test.*` file.
4. Commit your changes with a `fix:` prefix and a concise description.

### Running Tests
**Trigger:** To verify code correctness  
**Command:** `/run-tests`

1. Locate all test files matching the `*.test.*` pattern.
2. Use the project's preferred method (e.g., Xcode, CLI) to run tests.
3. Review test results and address any failures.

## Testing Patterns

- Test files follow the `*.test.*` naming pattern (e.g., `CompassView.test.swift`).
- The specific testing framework is unknown; use standard Swift/XCTest patterns unless otherwise specified.
- Place tests alongside or near the code they test for clarity and maintainability.

  Example test file:
  ```swift
  import XCTest
  @testable import solo_compass

  class CompassViewTests: XCTestCase {
      func testHeadingCalculation() {
          let compass = CompassView()
          XCTAssertEqual(compass.calculateHeading(), 90)
      }
  }
  ```

## Commands

| Command         | Purpose                                         |
|-----------------|-------------------------------------------------|
| /create-feature | Scaffold a new feature or component             |
| /fix-bug        | Start the bug fixing workflow                   |
| /run-tests      | Run all tests in the codebase                   |
```
