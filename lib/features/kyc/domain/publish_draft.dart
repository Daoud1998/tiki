// This file intentionally re-exports the canonical PublishDraft model used by the
// publish/edit wizard.
//
// Reason: the project previously had two different PublishDraft classes with the
// same name (one under /publish and one under /kyc). Dart treats them as
// different types, which caused invalid_assignment / argument_type_not_assignable
// errors when Lists were passed between layers.
//
// Keeping this file (as a re-export) preserves old import paths while ensuring a
// single PublishDraft type across the app.

export '../../publish/presentation/domain/publish_draft.dart';
