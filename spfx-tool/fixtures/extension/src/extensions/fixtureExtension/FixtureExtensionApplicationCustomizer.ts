import { BaseApplicationCustomizer } from '@microsoft/sp-application-base';

export interface IFixtureExtensionApplicationCustomizerProperties {}

export default class FixtureExtensionApplicationCustomizer
  extends BaseApplicationCustomizer<IFixtureExtensionApplicationCustomizerProperties> {

  public onInit(): Promise<void> {
    return Promise.resolve();
  }
}
