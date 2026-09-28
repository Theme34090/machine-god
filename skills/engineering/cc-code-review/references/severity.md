## Severity

The tiers below are the only severity vocabulary. A repo guideline that defines its own tiers does not replace these; it may name additional areas of concern for critical.

- **critical**: an outage, or wrong data served or written, for all users on a common path, with the component and the concrete scenario named. Any defect in an area of concern is critical regardless of how many users it reaches: cross-tenant read or write, money arithmetic, persisted wrong data, plus any area the repo's guidelines name.
- **high**: wrong business logic that reaches users widely, or a hard failure that blocks a user from completing a task.
- **medium**: wrong business logic on an uncommon path reaching few users, or a failure the user can work around.
- **cosmetic**: wrong copy, colour, or styling.

There is no tier below medium. A real defect that falls below medium and is not cosmetic is not reported.
