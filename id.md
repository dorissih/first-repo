VDI Cutover Plan – Old VDI to New VDI Migration
Prepared by: Doris Sih
Date: [Insert Date]
Change Ticket ID: CHG-2025-XXX

1. Activity Overview
Purpose:
To migrate all active users from the legacy Omnissa Horizon VDI pools (vSphere-backed) to newly provisioned VDI pools on upgraded infrastructure. This migration aims to improve system performance, security compliance, and resource scalability while minimizing downtime for end users.

Scope:

In-Scope:

All production VDI pools currently hosted on the old Horizon environment.

User profiles and entitlements.

Application access via App Volumes.

Out-of-Scope:

Development or test VDI pools.

Non-Horizon-based remote access solutions.

Change Window:

Date: [Insert Date]

Time: 22:00 – 02:00 (Off-hours to reduce impact).

Teams Involved:

VDI Team: Pool configuration, entitlement changes, post-checks.

Network Team: DNS updates, load balancer changes.

Help Desk: User communication and first-line support.

Application Owners: Application validation.

2. Review of Test Plan / Results / Participants
Test Plan Summary:

Verified that new VDI pools are fully provisioned and accessible.

Conducted user acceptance testing (UAT) with selected pilot users.

Tested critical business applications in new environment.

Validated profile redirection and folder redirection.

Monitored CPU, memory, and storage latency during test logins.

Test Results:

Login Performance: Average login time improved by 35%.

Application Load Times: Reduced by 20%.

No critical failures observed during pilot.

Minor printing issue with one printer mapping script – resolved before cutover.

Test Participants:

Pilot Users: 15 users from Finance, HR, and IT departments.

Technical Staff:

VDI Administrators: [Names]

Network Engineers: [Names]

Application Owners: [Names]

3. Pre-Cutover Checks
✅ New Horizon pools created, powered on, and fully patched.

✅ App Volumes packages attached to relevant pools.

✅ DNS and load balancer configurations prepared for update.

✅ AD groups for entitlements created and verified.

✅ Horizon Connection Servers healthy and in sync.

✅ Snapshot of old VDI pools taken for rollback safety.

✅ Rollback steps documented and validated.

✅ Help desk briefing completed.

4. Execution Plan
Step	Description	Responsible Party	Estimated Duration
1	Disable logins to old VDI pools	VDI Admin	10 min
2	Remove user entitlements from old pools	VDI Admin	10 min
3	Assign user entitlements to new VDI pools	VDI Admin	15 min
4	Update DNS / load balancer to point to new pools	Network Team	15 min
5	Test login with admin and pilot user accounts	VDI Admin	20 min
6	Monitor Horizon events and performance metrics	VDI Admin	1 hr
7	Notify help desk of cutover completion	Project Lead	5 min

5. Post-Cutover Checks
Verify that 100% of entitled users can log in successfully.

Confirm application accessibility (via App Volumes).

Validate that profile redirection is working.

Monitor system performance (CPU, RAM, disk latency) for at least 1 hour post-cutover.

Review Horizon event logs for warnings or errors.

Confirm external access via Unified Access Gateway (UAG).

Gather user feedback from pilot group.

6. Rollback Plan
Rollback Trigger Conditions:

More than 30% of users unable to log in.

Critical business application outage with no workaround.

System instability impacting performance.

Rollback Steps:

Re-enable logins to old VDI pools.

Revert DNS/load balancer changes to original configuration.

Remove new pool entitlements and restore old entitlements.

Notify users to log back into old VDI pools.

Log and escalate root cause for failure.

Rollback Time Estimate: ~45 minutes to full restoration.

Rollback Communication:

Help desk to notify affected users immediately via email and Teams chat.

IT Change Manager to update change record with rollback details.
