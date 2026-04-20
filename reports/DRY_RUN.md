# Todoist SAP Reorg Dry Run

- Snapshot: `2026-04-13T09:53:19+02:00`
- Root project: `📤 SAP`
- Current `📤 SAP` root tasks: `14`
- Current `Inbox` tasks: `0`

## Projects to Create
- None. The SAP root project and target child projects already exist.

## Sections to Create
- `People`: create section `1:1 prep`
- `People`: create section `follow-ups`
- `People`: create section `hiring`
- `People`: create section `performance actions`
- `Projects`: create section `AI / Automation`
- `Projects`: create section `Reporting`
- `Projects`: create section `Tooling / ISD Hub`
- `Projects`: create section `E2E / TCO`
- `Projects`: create section `other active`
- `Operations`: create section `leadership`
- `Operations`: create section `team meetings`
- `Operations`: create section `supplier / vendor`
- `Operations`: create section `security`
- `Operations`: create section `admin`
- `Services`: create section `General`
- `Services`: create section `Council`
- `Services`: create section `ATLAS / IBM`
- `Services`: create section `AppOps`
- `Services`: create section `Cloud ALM`
- `Services`: create section `CAS FRUN / ESP`
- `Services`: create section `BDC / SNOW / JIRA`

## Labels to Create
- Create label `@waiting`
- Create label `@1to1`
- Create label `@decision`
- Create label `@email`
- Create label `@deep`

## Task Renames and Moves
- `J4C Expert?` from `📤 SAP`: rename to `Decide J4C expert approach`; move to `Operations / admin`; add labels `@decision`
- `J4C prep` from `📤 SAP`: rename to `Prepare J4C meeting`; move to `Operations / admin`
- `Security Concept anpassen mit Ralf 0900` from `📤 SAP`: rename to `Update security concept with Ralf`; move to `Operations / security`
- `AI Project` from `📤 SAP`: rename to `Review AI project status`; move to `Projects / AI / Automation`
- `Rollout Abhijit AI` from `📤 SAP`: rename to `[Abhijit] Clarify AI rollout next step`; move to `Projects / AI / Automation`
- `Proposal E2E Delivery` from `📤 SAP`: rename to `Review E2E delivery proposal`; move to `Projects / E2E / TCO`
- `Reporting Project` from `📤 SAP`: rename to `Review reporting project status`; move to `Projects / Reporting`
- `application operations dashboard rollout stuff?` from `📤 SAP`: rename to `Define AppOps dashboard rollout next steps`; move to `Services / AppOps`
- `Demo Landschaft restriktiv (appops cockpit)` from `📤 SAP`: rename to `Clarify demo landscape restrictions for AppOps cockpit`; move to `Services / AppOps`

## Projects to Archive
- None. No archive candidates are currently safe to archive automatically.

## Manual Review
- `Andreas Krueckendorf` in `📤 SAP`: Marked for manual review in config.
- `External Roadmap` in `📤 SAP`: Marked for manual review in config.
- `IT Ops Model https://lucid.app/lucidchart/a0d9e526-d1f3-42d2-b8da-e3dd5bf2b89d/edit?invitationId=inv_f2f6eea7-89ea-467c-828f-49238b2069f8&page=0_0#` in `📤 SAP`: Marked for manual review in config.
- `Reifen` in `📤 SAP`: Marked for manual review in config.
- `Service Desk Service --> including AI/Automation` in `📤 SAP`: Marked for manual review in config.

## Ignored Out-of-Scope Items
- None.

## Review Before Apply
- Confirm the section layout in `todoist_target.yaml`.
- Confirm the exact title overrides and keyword routes in `todoist_migration_plan.yaml`.
- Review every manual-review item before any apply run.
- Confirm the label replacement policy, because migrated SAP tasks will drop configured legacy SAP labels.
- Confirm that no task listed under manual review should be moved automatically before running apply.

## Warnings
- This snapshot was generated from Todoist MCP read-only observations because TODOIST_API_TOKEN was not present in the local shell.
- The live Todoist state changed during inspection: the sample fuzzy work tasks were no longer in Inbox and were observed directly under 📤 SAP.
