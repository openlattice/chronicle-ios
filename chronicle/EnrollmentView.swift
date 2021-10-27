//
//  EnrollmentView.swift
//  chronicle
//
//  Created by Alfonce Nzioka on 8/3/21.
//

import SwiftUI

struct EnrollmentView: View {
    
    @ObservedObject var enrollmentViewModel: EnrollmentViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                AppHeader()
                Text("Do you have an organization ID?")
                    .padding(.bottom)
                RadioButtonGroup(hasOrgId: $enrollmentViewModel.withOrgId)

                if enrollmentViewModel.withOrgId == true {
                    InputFieldView(label: "Enter your Organization ID", inputId: $enrollmentViewModel.organizationId, invalidInput: $enrollmentViewModel.invalidOrganizationId)
                }
                InputFieldView(label: "Enter your Study ID", inputId: $enrollmentViewModel.studyId, invalidInput: $enrollmentViewModel.invalidStudyId)
                InputFieldView(label: "Enter your Participant ID", inputId: $enrollmentViewModel.participantId, invalidInput: $enrollmentViewModel.invalidParticipantId)
                HStack {
                    Spacer()
                    if enrollmentViewModel.enrolling == true {
                        ProgressView().padding(10)
                    }
                    else {
                        Button(action: {
                            Task {
                                await enrollmentViewModel.enroll()
                            }
                        }, label: {
                            Text("Enroll Device")
                                .foregroundColor(.white)
                                .padding(10)
                        })
                            .background(Color.primaryPurple)
                        .cornerRadius(8)
                        .disabled(enrollmentViewModel.enrolling == true)
                    }
                }
                if enrollmentViewModel.showEnrollmentError {
                    EnrollmentFailureMessage()
                }
                Spacer()
            }
            .padding(.horizontal)
            .textFieldStyle(.roundedBorder)
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var model = EnrollmentViewModel()
    static var previews: some View {
        EnrollmentView(enrollmentViewModel: model)
        EnrollmentView(enrollmentViewModel: model).preferredColorScheme(.dark)
    }
}
