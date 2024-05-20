//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import StreamChat
import SwiftUI

public struct PollAttachmentView<Factory: ViewFactory>: View {
    
    @Injected(\.chatClient) var chatClient
    @Injected(\.fonts) var fonts
    @Injected(\.colors) var colors
    
    private let factory: Factory
    private let message: ChatMessage
    private let isFirst: Bool
    
    @StateObject var viewModel: PollAttachmentViewModel
    
    public init(
        factory: Factory,
        message: ChatMessage,
        poll: Poll,
        isFirst: Bool
    ) {
        self.factory = factory
        self.message = message
        self.isFirst = isFirst
        _viewModel = StateObject(
            wrappedValue: PollAttachmentViewModel(
                message: message,
                poll: poll
            )
        )
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(poll.name)
                        .font(fonts.bodyBold)
                    Spacer()
                }
                
                HStack {
                    Text(subtitleText)
                        .font(fonts.caption1)
                        .foregroundColor(Color(colors.textLowEmphasis))
                    Spacer()
                }
            }
            
            ForEach(options.prefix(10)) { option in
                PollOptionView(
                    viewModel: viewModel,
                    option: option,
                    optionVotes: poll.voteCountsByOption?[option.id],
                    maxVotes: poll.voteCountsByOption?.values.max()
                )
            }
            
            if options.count > 10 {
                Button {
                    viewModel.allOptionsShown = true
                } label: {
                    Text("See \(options.count - 10) more options")
                }
                .fullScreenCover(isPresented: $viewModel.allOptionsShown) {
                    PollAllOptionsView(viewModel: viewModel)
                }
            }
            
            if viewModel.showSuggestOptionButton {
                Button {
                    viewModel.suggestOptionShown = true
                } label: {
                    Text("Suggest an option")
                }
                .modifier(
                    SuggestOptionModifier(
                        title: "Suggest an option",
                        showingAlert: $viewModel.suggestOptionShown,
                        text: $viewModel.suggestOptionText,
                        submit: {
                            viewModel.suggest(option: viewModel.suggestOptionText)
                        }
                    )
                )
            }
            
            if viewModel.showAddCommentButton {
                Button {
                    viewModel.addCommentShown = true
                } label: {
                    Text("Add a comment")
                }
                .modifier(
                    SuggestOptionModifier(
                        title: "Add a comment", 
                        showingAlert: $viewModel.addCommentShown,
                        text: $viewModel.commentText,
                        submit: {
                            viewModel.add(comment: viewModel.commentText)
                        }
                    )
                )
            }
            
            if viewModel.poll.answersCount > 0 {
                Button {
                    viewModel.allCommentsShown = true
                } label: {
                    Text("View \(viewModel.poll.answersCount) comments")
                }
                .fullScreenCover(isPresented: $viewModel.allCommentsShown) {
                    PollCommentsView(poll: viewModel.poll, pollController: viewModel.pollController)
                }
            }
            
            Button {
                viewModel.pollResultsShown = true
            } label: {
                Text("View results")
            }
            .fullScreenCover(isPresented: $viewModel.pollResultsShown) {
                PollResultsView(viewModel: viewModel)
            }
            
            if viewModel.showEndVoteButton {
                Button {
                    viewModel.endVote()
                } label: {
                    Text("End vote")
                }
            }
        }
        .padding()
        .modifier(
            factory.makeMessageViewModifier(
                for: MessageModifierInfo(
                    message: message,
                    isFirst: isFirst
                )
            )
        )
        
    }
    
    private var poll: Poll {
        viewModel.poll
    }
    
    private var options: [PollOption] {
        poll.options.sorted(by: { $0.text < $1.text })
    }
    
    private var subtitleText: String {
        if poll.isClosed == true {
            return "Vote ended"
        } else if poll.enforceUniqueVote == true {
            return "Select one"
        } else if let maxVotes = poll.maxVotesAllowed {
            return "Select up to \(maxVotes)"
        } else {
            return "Select one or more"
        }
    }
}

extension PollOption: Identifiable {}

struct SuggestOptionModifier: ViewModifier {
    
    var title: String
    @Binding var showingAlert: Bool
    @Binding var text: String
    var submit: () -> ()
    
    func body(content: Content) -> some View {
        if #available(iOS 15.0, *) {
            content
                .alert(title, isPresented: $showingAlert) {
                    TextField("Enter a new option", text: $text)
                    Button("Cancel") {
                        showingAlert = false
                    }
                    Button("Add", action: submit)
                } message: {
                    Text("")
                }
        } else {
            //TODO: Add for iOS < 15.
            content
        }
    }
}

struct PollOptionView: View {
    
    @ObservedObject var viewModel: PollAttachmentViewModel
    
    var option: PollOption
    var optionFont: Font = InjectedValues[\.fonts].body
    var optionVotes: Int?
    var maxVotes: Int?
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                if !viewModel.poll.isClosed {
                    Button {
                        if viewModel.optionVotedByCurrentUser(option) {
                            viewModel.removePollVote(for: option)
                        } else {
                            viewModel.castPollVote(for: option)
                        }
                    } label: {
                        if viewModel.optionVotedByCurrentUser(option) {
                            Image(systemName: "checkmark.circle.fill")
                        } else {
                            Image(systemName: "circle")
                        }
                    }
                }

                Text(option.text)
                    .font(optionFont)
                Spacer()
                HStack(spacing: -4) {
                    ForEach(option.latestVotes.suffix(2)
                        .sorted(by: { $0.createdAt > $1.createdAt })
                    ) { vote in
                        MessageAvatarView(
                            avatarURL: vote.user?.imageURL,
                            size: .init(width: 20, height: 20)
                        )
                    }
                }
                Text("\(viewModel.poll.voteCountsByOption?[option.id] ?? 0)")
            }
            
            if let maxVotes {
                PollVotesIndicatorView(
                    optionVotes: optionVotes ?? 0,
                    maxVotes: maxVotes
                )
                .padding(.leading, 24)
            }
        }
    }
}

struct PollVotesIndicatorView: View {
    
    @Injected(\.colors) var colors
    
    var optionVotes: Int
    var maxVotes: Int
    
    private let height: CGFloat = 4
    
    var body: some View {
        GeometryReader { reader in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(colors.background2))
                    .frame(width: reader.size.width, height: height)

                RoundedRectangle(cornerRadius: 8)
                    .fill(colors.tintColor)
                    .frame(width: reader.size.width * ratio, height: height)
            }
            .frame(height: height)
        }
    }
    
    var ratio: CGFloat {
        CGFloat(optionVotes) / CGFloat(maxVotes)
    }
}