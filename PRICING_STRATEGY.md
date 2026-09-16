Yes. We estimate this with a **unit economics model**, then enforce it in billing with **entitlements + quotas**.

**Cost Model**
For each Voxa feature, estimate cost per user action:

| Feature | Cost driver |
|---|---|
| Realtime tutor | audio input minutes + audio output minutes + text tokens |
| Ask anything | input tokens + output tokens |
| Translation | input tokens + output tokens |
| Image translation | image/vision input tokens + output tokens |
| Vocabulary tests | generated quiz tokens + grading/explanation tokens |
| Debrief/session summary | transcript size + output summary tokens |
| Infrastructure | Azure Functions, storage, tables, networking, logs, auth, monitoring |

OpenAI says you can track usage either from the Usage Dashboard or from API responses, which include token usage fields like input/output/total tokens depending on endpoint. Source: [OpenAI usage docs](https://help.openai.com/en/articles/10478918-reviewing-api-usage-and-costs).

So the practical formula is:

```text
monthly_cost =
  openai_text_cost
+ openai_audio_cost
+ openai_image_cost
+ azure_fixed_cost
+ azure_variable_cost
+ monitoring/logging_cost
+ app_store_commission_buffer
+ safety_margin
```

Where:

```text
openai_text_cost =
  (input_tokens / 1_000_000 * model_input_price)
+ (output_tokens / 1_000_000 * model_output_price)
```

For Realtime, we should estimate separately:

```text
realtime_cost_per_session =
  audio_input_minutes * input_audio_cost_per_minute
+ audio_output_minutes * output_audio_cost_per_minute
+ text_tokens_cost
```

The key thing: **we should instrument real usage during TestFlight**. Guessing from prompts is useful for first pricing, but billing should be based on actual observed median/p90/p99 usage.

**Pricing Recommendation**
I’d model three tiers:

| Tier | Price | Included usage |
|---|---:|---|
| Free | $0 | Small monthly allowance, enough to try Voxa |
| Plus | ~$7.99-$9.99/mo | Reasonable daily tutor/translation/practice usage |
| Pro | ~$14.99-$19.99/mo | Higher voice minutes, image translation, heavier usage |

Apple takes commission from IAP revenue. Small Business Program is currently 15% if eligible. Source: [Apple Small Business Program](https://developer.apple.com/app-store/small-business-program/). Otherwise assume 30% initially, with subscriptions improving after long-term renewals depending on Apple’s rules. Source: [Apple subscriptions](https://developer-rno.apple.com/app-store/subscriptions/).

So if you charge `$9.99/mo`, do **not** budget as if you receive `$9.99`.

Rough net:

```text
Small Business net ≈ $9.99 * 0.85 = $8.49 before tax/adjustments
Standard net ≈ $9.99 * 0.70 = $6.99 before tax/adjustments
```

Your usage allowance must fit comfortably below that.

**How To Implement Billing**
Not code now, but architecturally:

1. **Use StoreKit 2 in iOS**
   The app lets users buy/restore subscriptions through Apple IAP.

2. **Backend owns entitlements**
   The iOS app sends transaction info to Voxa backend. Backend verifies it with Apple, then stores entitlement state:
   - user id
   - product id
   - subscription status
   - renewal date
   - environment: sandbox/production
   - original transaction id
   - app account token if used

3. **Use App Store Server API**
   Backend checks subscription status server-side. Apple’s App Store Server API exists specifically to manage customer transaction and subscription status. Source: [Apple App Store Server API](https://developer.apple.com/documentation/appstoreserverapi?changes=_2_5).

4. **Use App Store Server Notifications**
   Apple notifies your backend when renewals, cancellations, billing retry, refunds, and expirations happen. The backend updates entitlements without relying only on the app opening.

5. **Every AI endpoint checks entitlement + quota**
   Before calling OpenAI:
   - Is the user authenticated?
   - What plan do they have?
   - Have they exceeded today/month quota?
   - Is this feature allowed on their plan?
   - Would this request exceed max cost/request?

6. **Record usage in your own ledger**
   Every OpenAI-backed request should write a usage event:
   - user id
   - feature
   - model
   - estimated/requested units
   - actual input/output tokens if returned
   - audio seconds in/out if known
   - image count/size
   - success/failure
   - cost estimate
   - correlation id

7. **Hard-stop quotas**
   This is the thing that protects you:
   - free user: maybe 5 voice minutes/day, 20 text tools/day
   - paid user: maybe 30-60 voice minutes/day
   - image translation: stricter cap, because it can be expensive/heavy
   - absolute monthly cap per user even on paid plans

8. **Global spend kill switch**
   If OpenAI spend exceeds a daily threshold, degrade gracefully:
   - disable image translation
   - switch to cheaper model
   - reduce realtime session max duration
   - temporarily block free-tier AI calls

**My Recommendation**
Use **subscription + quotas**, not pay-per-token to users.

Users should not have to think about tokens. They should see:

- Free: “Try Voxa”
- Plus: “More tutor time and translations”
- Pro: “Heavy practice and voice”

Internally, we think in tokens, minutes, and cost ceilings.

For #85/App Store readiness, I’d add a billing/cost-control work item before launch:

**“Implement subscription entitlements, OpenAI usage ledger, and per-plan AI quotas.”**

That is the bridge between “this app works” and “this app cannot bankrupt you.”
