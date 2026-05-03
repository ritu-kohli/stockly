import SwiftUI

struct DisclaimerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.orange)
                    .padding(.top, 40)

                VStack(spacing: 8) {
                    Text("Important Disclaimer")
                        .font(.title2.bold())
                    Text("Please read before using")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    disclaimerPoint(
                        icon: "chart.bar.xaxis",
                        title: "Technical Analysis Only",
                        body: "The signals shown (Strong, Positive, Neutral, Caution, Weak, Alert) are based on technical indicators only. They are not buy or sell recommendations."
                    )
                    disclaimerPoint(
                        icon: "brain",
                        title: "Not Financial Advice",
                        body: "Nothing in this app constitutes financial advice, investment advice, or a recommendation to buy or sell any security. Always do your own research."
                    )
                    disclaimerPoint(
                        icon: "newspaper",
                        title: "AI Sentiment is Estimated",
                        body: "News sentiment analysis is AI-estimated and may be inaccurate. Verify all news independently before making any trading decisions."
                    )
                    disclaimerPoint(
                        icon: "dollarsign.circle",
                        title: "Real Money Risk",
                        body: "Investing involves risk of loss. Past performance does not guarantee future results. You are solely responsible for your investment decisions."
                    )
                }
                .padding(.horizontal, 24)

                Spacer()

                Button(action: {
                    UserDefaults.standard.set(true, forKey: "disclaimer_shown")
                    dismiss()
                }) {
                    Text("I Understand — Continue")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .interactiveDismissDisabled(true) // must tap the button
    }

    private func disclaimerPoint(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}
