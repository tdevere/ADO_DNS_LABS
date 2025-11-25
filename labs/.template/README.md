# Lab N: [Scenario Title]

## 🎯 The Situation

**[Day], [Time]:** [Event that triggered the issue]

**What you know:**
- [Symptom 1]
- [Symptom 2]
- [Symptom 3]

**What you don't know:**
- [Hidden cause 1]
- [Hidden cause 2]

**Your mission:** [Investigation goal in one sentence]

> **Real-World Context**
> [Why this scenario matters in production. When does this happen? What makes it tricky?]

---

## 💥 Start the Lab

### Step 1: Simulate the [Fault Type]

Run this command to simulate [what infrastructure team did]:
```bash
./break-lab.sh labN
```

[Explain what this represents in real-world terms]

### Step 2: Observe the Pipeline Failure

[Where to look, what error students will see]

**Key observation:** [What the error message tells us]

---

## 🔍 Investigation: Systematic Troubleshooting

### STEP 1: Scope the Problem (What Do We Know?)

Before jumping into Azure CLI commands, answer these questions:

1. **What symptom are we seeing?**
   - Pipeline stage: `___________________`
   - Error type: `___________________`
   - Timing: `___________________`

2. **What's the context?**
   - [Question about environment]
   - [Question about history]

3. **What should we check first?**
   - [Diagnostic path guidance]

**For this lab scenario:**
- [Key facts about this specific scenario]
- [What makes this different from other labs]

---

### STEP 2: Analyze the Error Message

[Show error output, teach students to decode it]

**Error Symptom Decision Matrix:**

| Symptom | Investigation Path |
|---------|-------------------|
| [Symptom A] | [Check X] |
| [Symptom B] | [Check Y] |

---

### STEP 3: Build the Architecture Context

[Question: "Draw the architecture on paper. What components are involved?"]

```mermaid
[Architecture diagram showing the components involved]
```

**Key Questions:**
1. [Question about data flow]
2. [Question about DNS path]
3. [Question about network boundaries]

---

### STEP 4: [Lab-Specific Diagnostic Step]

**Goal:** [What are we trying to determine?]

[CLI commands to run with explanation]

```bash
[Command 1]
```

**Expected output:**
```
[Show what they should see]
```

**Interpretation:** [What this tells us]

---

### STEP 5: [Investigation Continues]

[Continue diagnostic process with more commands and analysis]

---

### STEP N: Compare (Root Cause Identification)

[Comparison table showing what should be vs what is]

| Resource | Expected | Actual | Match? |
|----------|----------|--------|--------|
| [Thing 1] | [value] | [value] | ? |
| [Thing 2] | [value] | [value] | ? |

**Root Cause:** [Clear explanation of why the issue is happening]

---

## 🛠️ Fix the Issue

You have two choices. As a Support Engineer, you often have to decide between a quick "Hotfix" to get production running and a "Proper" fix to ensure consistency.

### Option 1: The "Hotfix" (Manual Azure CLI)
*Use this when production is down and you need immediate recovery.*

```bash
# [Azure CLI commands to fix the issue manually]
```

### Option 2: The "Proper" Fix (Infrastructure as Code)
*Use this to ensure your Terraform state matches reality.*

```bash
./fix-lab.sh labN
```
*Note: In this lab, `fix-lab.sh` just runs `terraform apply` to enforce the configuration defined in `main.tf`.*

---

## ✅ Verify the Fix

### 1. Check [Primary Symptom] (from the VM)

[Verification commands]

```bash
[Command to verify fix]
```

**Expected output:**
```
[What success looks like]
```

### 2. Re-run the Pipeline
1. Go back to Azure DevOps.
2. Find your failed pipeline run.
3. Click **"Rerun failed jobs"**.

It should now succeed (green checkmarks everywhere)! 🎉

---

## 🧠 What You Learned

**Key Concepts:**

1. **[Concept 1 Title]**  
   [Explanation of what this means and why it matters]

2. **[Concept 2 Title]**  
   [Explanation]

3. **[Concept 3 Title]**  
   [Explanation]

**Reusable Troubleshooting Process:**

Next time [similar scenario happens]:

1. [Step 1]
2. [Step 2]
3. [Step 3]
4. [Step 4]
5. [Step 5]
6. [Step 6]

---

### 📺 Recommended Watching

[Optional: Videos, docs, blog posts that deepen understanding]

---

## 🎓 Next Steps

- **Lab [N+1]:** [Next scenario title and brief description]
- **Lab [N+2]:** [Another scenario]

Good luck! 🚀
