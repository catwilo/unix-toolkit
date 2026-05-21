import { Version } from '@microsoft/sp-core-library';
import { BaseClientSideWebPart } from '@microsoft/sp-webpart-base';

export interface IFixtureReactWebpartWebPartProps {}

export default class FixtureReactWebpartWebPart
  extends BaseClientSideWebPart<IFixtureReactWebpartWebPartProps> {

  public render(): void {
    this.domElement.innerHTML = `<div>fixture-react-webpart</div>`;
  }

  protected get dataVersion(): Version {
    return Version.parse('1.0');
  }
}
