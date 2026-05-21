import { BaseAdaptiveCardExtension } from '@microsoft/sp-adaptive-card-extension-base';

export interface IFixtureAceAdaptiveCardExtensionProps {}
export interface IFixtureAceAdaptiveCardExtensionState {}

export default class FixtureAceAdaptiveCardExtension
  extends BaseAdaptiveCardExtension<
    IFixtureAceAdaptiveCardExtensionProps,
    IFixtureAceAdaptiveCardExtensionState
  > {

  public get iconProperty(): string {
    return 'BulletedList';
  }

  public async onInit(): Promise<void> {
    this.state = {};
    return Promise.resolve();
  }

  public get title(): string {
    return 'fixture-ace';
  }
}
